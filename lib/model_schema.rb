require 'sequel'
require 'model_schema/version'

module ModelSchema
  DEFAULT_COL_OPTS = {
    :name => nil,
    :type => nil,
    :collate => nil,
    :default => nil,
    :deferrable => nil,
    :index => nil,
    :key => [:id],
    :null => true,
    :on_delete => :no_action,
    :on_update => :no_action,
    :primary_key => false,
    :primary_key_constraint_name => nil,
    :serial => false,
    :unique => false,
    :unique_constraint_name => nil,
    :table => nil,
  }

  COL_EXTRA = :extra
  COL_MISSING = :missing
  COL_MISMATCH = :mismatch

  class SchemaError < StandardError
    attr_reader :schema_diffs

    def initialize(table_name, schema_diffs)
      @table_name = table_name
      @schema_diffs = schema_diffs
    end

    def diffs_by_type(type)
      @schema_diffs.select {|diff| diff[:type] == type}
    end

    def dump_col(col)
      col_no_default = col.select do |key, value|
        value != DEFAULT_COL_OPTS[key]
      end

      name = col_no_default.delete(:name)
      type = col_no_default.delete(:type)
      options_str = col_no_default.length > 0 ?
                    ", #{col_no_default.inspect}" : ''

      if type.is_a?(Class)
        "#{type.inspect} #{name.inspect}#{options_str}"
      else
        "column #{name.inspect}, #{type.inspect}#{options_str}"
      end
    end

    def dump_extra_diffs
      extra_diffs = diffs_by_type(COL_EXTRA)

      if extra_diffs.length > 0
        header = "Table #{@table_name} has extra columns:\n"
        diff_str = extra_diffs.map {|diff| dump_col(diff[:col])}.join("\n\t")
        "#{header}\n\t#{diff_str}\n"
      end
    end

    def dump_missing_diffs
      missing_diffs = diffs_by_type(COL_MISSING)

      if missing_diffs.length > 0
        header = "Table #{@table_name} is missing columns:\n"
        diff_str = missing_diffs.map {|diff| dump_col(diff[:col])}.join("\n\t")
        "#{header}\n\t#{diff_str}\n"
      end
    end

    def dump_mismatch_diffs
      mismatch_diffs = diffs_by_type(COL_MISMATCH)

      if mismatch_diffs.length > 0
        header = "Table #{@table_name} has mismatched columns:\n"
        diff_str = mismatch_diffs.map do |diff|
          "actual:    #{dump_col(diff[:db_col])}\n\t" +
          "expected:  #{dump_col(diff[:exp_col])}"
        end.join("\n\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def to_s
      parts = [dump_extra_diffs, dump_missing_diffs, dump_mismatch_diffs]
      parts.compact.join("\n")
    end
  end

  class MissingTableError < StandardError; end

  module ClassMethods
    def model_schema(options={}, &block)
      db.extension(:schema_dumper)

      begin
        db_generator = db.send(:dump_table_generator, table_name, :same_db => true)
      rescue Sequel::DatabaseError => error
        if error.message.include?('PG::UndefinedTable:')
          fail MissingTableError, "Table #{table_name} doesn't exist."
        end
      end

      # avoid using Sequel::Model.db_schema method because it has odd caching
      # behavior across classes that breaks tests
      table_schema = Hash[db.schema(table_name)]

      db_columns = db_generator.columns.each do |c|
        col_schema = table_schema[c[:name]]
        type_hash = db.column_schema_to_ruby_type(col_schema)

        type = type_hash[:type]
        # TODO: comment this
        c[:type] = type if type_hash.length != 1 || type != String
      end
      db_columns = Hash[db_columns.map {|c| [c[:name], c]}]

      exp_generator = db.create_table_generator(&block)
      exp_columns = Hash[exp_generator.columns.map {|c| [c[:name], c]}]

      check_all_columns(db_columns, exp_columns)
      # TODO: check indexes
      # TODO: no indexes option
    end

    # Check if all database columns match the expected columns.
    def check_all_columns(db_columns, exp_columns)
      schema_diffs = []

      extra_keys = db_columns.keys - exp_columns.keys
      extra_keys.each do |ek|
        schema_diffs << {:type => COL_EXTRA, :col => db_columns[ek]}
      end

      missing_keys = exp_columns.keys - db_columns.keys
      missing_keys.each do |mk|
        schema_diffs << {:type => COL_MISSING, :col => exp_columns[mk]}
      end

      db_columns.each do |key, db_col|
        exp_col = exp_columns[key]
        next if !exp_col

        col_diff = check_col(db_col, exp_col)
        schema_diffs << col_diff if col_diff
      end

      if schema_diffs.length > 0
        raise SchemaError.new(table_name, schema_diffs)
      end
    end

    # Check if the given database column matches the expected column.
    def check_col(db_col, exp_col)
      # db_col is guaranteed to be valid, so we just check exp_col for extra keys
      invalid_keys = exp_col.keys - DEFAULT_COL_OPTS.keys
      message = "#{invalid_keys.join(', ')} are invalid options for column " +
                "#{exp_col[:name]}"
      fail KeyError, message if invalid_keys.length > 0

      db_col = DEFAULT_COL_OPTS.merge(db_col)
      exp_col = DEFAULT_COL_OPTS.merge(exp_col)
      type_literal = db.method(:type_literal)

      # db_col and exp_col now have the same keys; compare then
      match = db_col.all? do |key, value|
        if key == :type
          # types could either be strings or ruby types; normalize them
          type_literal.call(db_col).to_s == type_literal.call(exp_col).to_s
        else
          value == exp_col[key]
        end
      end

      match ? nil : {:type => COL_MISMATCH, :db_col => db_col, :exp_col => exp_col}
    end
  end
end
