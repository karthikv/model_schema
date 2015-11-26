module ModelSchema
  class SchemaError < StandardError
    COL_EXTRA = :extra
    COL_MISSING = :missing
    COL_MISMATCH = :mismatch

    attr_reader :schema_diffs

    def initialize(table_name, schema_diffs)
      @table_name = table_name
      @schema_diffs = schema_diffs
      @cached_generator_dumps = {}
    end

    def dump_col(generator, col_name)
      index = generator.columns.find_index {|c| c[:name] == col_name}
      if !@cached_generator_dumps.key?(generator)
        lines = generator.dump_columns.lines.map(&:strip)
        @cached_generator_dumps[generator] = lines
      end

      @cached_generator_dumps[generator][index]
    end

    def diffs_by_type(type)
      @schema_diffs.select {|diff| diff[:type] == type}
    end

    def dump_extra_diffs
      extra_diffs = diffs_by_type(COL_EXTRA)

      if extra_diffs.length > 0
        header = "Table #{@table_name} has extra columns:\n"
        diff_str = extra_diffs.map do |diff|
          dump_col(diff[:generator], diff[:col_name])
        end.join("\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def dump_missing_diffs
      missing_diffs = diffs_by_type(COL_MISSING)

      if missing_diffs.length > 0
        header = "Table #{@table_name} is missing columns:\n"
        diff_str = missing_diffs.map do |diff|
          dump_col(diff[:generator], diff[:col_name])
        end.join("\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def dump_mismatch_diffs
      mismatch_diffs = diffs_by_type(COL_MISMATCH)

      if mismatch_diffs.length > 0
        header = "Table #{@table_name} has mismatched columns:\n"
        diff_str = mismatch_diffs.map do |diff|
          "actual:    #{dump_col(diff[:db_generator], diff[:col_name])}\n\t" +
          "expected:  #{dump_col(diff[:exp_generator], diff[:col_name])}"
        end.join("\n\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def to_s
      parts = [dump_extra_diffs, dump_missing_diffs, dump_mismatch_diffs]
      parts.compact.join("\n")
    end
  end
end
