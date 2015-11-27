module ModelSchema
  # Tracks differences between the expected schema and database table schema.
  class SchemaError < StandardError
    TYPE_EXTRA = :extra
    TYPE_MISSING = :missing
    TYPE_MISMATCH = :mismatch

    attr_reader :schema_diffs

    # Creates a SchemaError for the given table with an array of schema
    # differences. Each element of schema_diffs should be a hash of the
    # following form:
    #
    # :field => if a column is different, use FIELD_COLUMNS;
    #           if an index is different, use FIELD_INDEXES
    # :type => if there's an extra column/index, use TYPE_EXTRA;
    #          if there's a missing column/index, use TYPE_MISSING;
    #          if there's a mismatched column/index, use TYPE_MISMATCH
    #
    # For TYPE_EXTRA and TYPE_MISSING:
    # :generator => the table generator that contains the extra/missing index/column
    # :elem => the missing index/column, as a hash from the table generator
    #
    # For TYPE_MISMATCH:
    # :db_generator => the db table generator
    # :exp_generator => the expected table generator
    # :db_elem => the index/column in the db table generator as a hash
    # :exp_elem => the index/column in the exp table generator as a hash
    def initialize(table_name, schema_diffs)
      @table_name = table_name
      @schema_diffs = schema_diffs
    end

    # Dumps a single column/index from the generator to its string representation.
    #
    # field: FIELD_COLUMNS for a column or FIELD_INDEXES for an index
    # generator: the table generator
    # elem: the index/column in the generator as a hash
    def dump_single(field, generator, elem)
      array = generator.send(field)
      index = array.find_index(elem)
      fail ArgumentError, "#{elem.inspect} not part of #{array.inspect}" if !index

      lines = generator.send(:"dump_#{field}").lines.map(&:strip)
      lines[index]
    end

    # Returns the diffs in schema_diffs that have the given field and type.
    def diffs_by_field_type(field, type)
      @schema_diffs.select {|diff| diff[:field] == field && diff[:type] == type}
    end

    # Dumps all diffs that have the given field and are of TYPE_EXTRA.
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

    # Dumps all diffs that have the given field and are of TYPE_MISSING.
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

    # Dumps all diffs that have the given field and are of TYPE_MISMATCH.
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

    # Combines all dumps into one cohesive error message.
    def to_s
      parts = FIELDS.flat_map do |field|
        [dump_extra_diffs(field),
         dump_missing_diffs(field),
         dump_mismatch_diffs(field)]
      end
      "#{@table_name} does not match expected schema.\n\n#{parts.compact.join("\n")}"
    end
  end
end
