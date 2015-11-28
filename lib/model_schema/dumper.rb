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
        p.banner = "Usage: dump_model_schema [options]"

        p.on('-m', '--model MODEL', 'Model file to dump schema in') do |model|
          opts[:model] = model
        end

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

      parser.parse(args)

      # model and connection are required
      abort 'Must provide a model file with -m or --model.' if !opts[:model]
      abort 'Must provide a connection string with -c or --connection.' if !opts[:connection]

      dump_model_schema(opts)
    end

    # Dumps the model schema based on the given options (see option parsing above).
    def self.dump_model_schema(opts)
      model_info = parse_model_file(opts[:model])
      abort "Couldn't find class that extends Sequel::Model" if !model_info

      db = Sequel.connect(opts[:connection])
      db.extension(:schema_dumper)

      klass = Class.new(Sequel::Model(model_info[:table_name]))
      klass.db = db

      # dump table generator given by model_schema
      generator = klass.send(:table_generator)
      commands = [generator.dump_columns, generator.dump_constraints,
                  generator.dump_indexes].reject{|s| s == ''}.join("\n\n")

      # account for indentation
      tab = opts[:tabbing] == 0 ? "\t" : ' ' * opts[:tabbing]
      schema_indentation = model_info[:indentation] + tab
      command_indentation = schema_indentation + tab

      commands = commands.lines.map {|l| l == "\n" ? l : command_indentation + l}.join
      commands = commands.gsub('=>', ' => ')

      dump_lines = ["#{schema_indentation}model_schema do\n",
                    "#{commands}\n",
                    "#{schema_indentation}end\n"]

      lines = model_info[:lines_before] + dump_lines + model_info[:lines_after]
      File.write(opts[:model], lines.join)
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
            abort "Can't find a symbol table name on line: #{line}"
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
