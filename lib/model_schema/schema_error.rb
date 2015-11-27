module ModelSchema
  # TODO: comment this
  class SchemaError < StandardError
    TYPE_EXTRA = :extra
    TYPE_MISSING = :missing
    TYPE_MISMATCH = :mismatch

    attr_reader :schema_diffs

    def initialize(table_name, schema_diffs)
      @table_name = table_name
      @schema_diffs = schema_diffs
      @cached_generator_dumps = {}
    end

    def dump_single(field, generator, elem)
      array = generator.send(field)
      index = array.find_index(elem)
      fail ArgumentError, "#{elem.inspect} not part of #{array.inspect}" if !index

      lines = generator.send(:"dump_#{field}").lines.map(&:strip)
      lines[index]
    end

    def diffs_by_field_type(field, type)
      @schema_diffs.select {|diff| diff[:field] == field && diff[:type] == type}
    end

    def dump_extra_diffs(field)
      extra_diffs = diffs_by_field_type(field, TYPE_EXTRA)

      if extra_diffs.length > 0
        header = "Table #{@table_name} has extra #{field}:\n"
        diff_str = extra_diffs.map do |diff|
          dump_single(field, diff[:generator], diff[:elem])
        end.join("\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def dump_missing_diffs(field)
      missing_diffs = diffs_by_field_type(field, TYPE_MISSING)

      if missing_diffs.length > 0
        header = "Table #{@table_name} is missing #{field}:\n"
        diff_str = missing_diffs.map do |diff|
          dump_single(field, diff[:generator], diff[:elem])
        end.join("\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def dump_mismatch_diffs(field)
      mismatch_diffs = diffs_by_field_type(field, TYPE_MISMATCH)

      if mismatch_diffs.length > 0
        header = "Table #{@table_name} has mismatched #{field}:\n"
        diff_str = mismatch_diffs.map do |diff|
          "actual:    #{dump_single(field, diff[:db_generator], diff[:db_elem])}\n\t" +
          "expected:  #{dump_single(field, diff[:exp_generator], diff[:exp_elem])}"
        end.join("\n\n\t")

        "#{header}\n\t#{diff_str}\n"
      end
    end

    def to_s
      parts = FIELDS.flat_map do |field|
        [dump_extra_diffs(field),
         dump_missing_diffs(field),
         dump_mismatch_diffs(field)]
      end
      "\n\n" + parts.compact.join("\n")
    end
  end
end
