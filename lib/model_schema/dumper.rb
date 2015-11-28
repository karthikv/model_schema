require 'optparse'

SEQUEL_MODEL_REGEX = /class\s+.*?<\s+Sequel::Model\((.*?)\)/
LEADING_WHITESPACE_REGEX = /^\s*/

module ModelSchema
  module Dumper
    # Parses options and then dumps the model schema.
    def self.run(args)
      opts = {}
      opts[:tabbing] = 2

      parser = OptionParser.new do |p|
        p.banner = 'Usage: dump_model_schema [options] model_file [model_file ...]'
        p.separator "\nDumps a valid model_schema block in each given model_file.\n\n"

        p.on('-c', '--connection CONNECTION',
             'Connection string for database') do |connection|
          opts[:connection] = connection
        end

        p.on('-t', '--tabbing TABBING', Integer,
                  'Number of spaces for tabbing, or 0 for hard tabs') do |tabbing|
          opts[:tabbing] = tabbing
        end

        p.on('-v', '--version', 'Print version') do
          puts ModelSchema::VERSION
          exit
        end

        p.on('-h', '--help', 'Print help') do
          puts parser
          exit
        end
      end

      model_files = parser.parse(args)

      # model and connection are required
      abort 'Must provide at least one model file.' if model_files.empty?
      abort 'Must provide a connection string with -c or --connection.' if !opts[:connection]

      db = Sequel.connect(opts[:connection])
      db.extension(:schema_dumper)

      if db.is_a?(Sequel::Postgres::Database)
        # include all Postgres type extensions so schema dumps are accurate
        db.extension(:pg_array, :pg_enum, :pg_hstore, :pg_inet, :pg_json,
                     :pg_range, :pg_row)
      end

      had_error = false
      model_files.each do |path|
        begin
          dump_model_schema(db, path, opts)
        rescue StandardError, SystemExit => error
          # SystemExit error messages are already printed by abort()
          $stderr.puts error.message if error.is_a?(StandardError)
          had_error = true
        end
      end

      exit 1 if had_error
    end

    # Dumps a valid model_schema into the given file path. Accepts options as
    # per the OptionParser above.
    def self.dump_model_schema(db, path, opts)
      model = parse_model_file(path)
      abort "In #{path}, couldn't find class that extends Sequel::Model" if !model

      klass = Class.new(Sequel::Model(model[:table_name]))
      klass.db = db
      klass.plugin(ModelSchema::Plugin)

      # dump table generator given by model_schema
      generator = klass.send(:table_generator)
      commands = [generator.dump_columns, generator.dump_constraints,
                  generator.dump_indexes].reject{|s| s == ''}.join("\n\n")

      # account for indentation
      tab = opts[:tabbing] == 0 ? "\t" : ' ' * opts[:tabbing]
      schema_indentation = model[:indentation] + tab
      command_indentation = schema_indentation + tab

      commands = commands.lines.map {|l| l == "\n" ? l : command_indentation + l}.join
      commands = commands.gsub('=>', ' => ')

      dump_lines = ["#{schema_indentation}model_schema do\n",
                    "#{commands}\n",
                    "#{schema_indentation}end\n"]

      lines = model[:lines_before] + dump_lines + model[:lines_after]
      File.write(path, lines.join)
    end

    # Parses the model file at the given path, returning a hash of the form:
    #
    # :table_name => the model table name
    # :lines_before => an array of lines before the expected model schema dump
    # :lines_after => an array of lines after the expected model schema dump
    # :indentation => the indentation (leading whitespace) of the model class
    #
    # Returns nil if the file couldn't be parsed.
    def self.parse_model_file(path)
      lines = File.read(path).lines

      lines.each_with_index do |line, index|
        match = SEQUEL_MODEL_REGEX.match(line)

        if match
          # extract table name as symbol
          table_name = match[1]
          if table_name[0] == ':'
            table_name = table_name[1..-1].to_sym
          else
            abort "In #{path}, can't find a symbol table name in line: #{line}"
          end

          # indentation for model_schema block
          indentation = LEADING_WHITESPACE_REGEX.match(line)[0]

          return {
            :table_name => table_name.to_sym,
            :lines_before => lines[0..index],
            :lines_after => lines[(index + 1)..-1],
            :indentation => indentation,
          }
        end
      end

      nil
    end
  end
end
