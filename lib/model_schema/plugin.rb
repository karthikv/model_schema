require 'sequel'

module ModelSchema
  module Plugin
    module ClassMethods
      def model_schema(options={}, &block)
        db.extension(:schema_dumper)

        db_generator = table_generator
        exp_generator = db.create_table_generator(&block)

        check_all_columns(db_generator, exp_generator)
        # TODO: check indexes
        # TODO: no indexes option
      end

      private

      # Returns the table generator representing this table.
      def table_generator
        begin
          db_generator_explicit = db.send(:dump_table_generator, table_name,
                                          :same_db => true)
          db_generator_generic = db.send(:dump_table_generator, table_name)
        rescue Sequel::DatabaseError => error
          if error.message.include?('PG::UndefinedTable:')
            fail NameError, "Table #{table_name} doesn't exist."
          end
        end

        # db_generator_explicit contains explicit string types for each field,
        # specific to the current database; db_generator_generic contains ruby
        # types for each field. When there's no corresponding ruby type,
        # db_generator_generic defaults to the String type. We'd like to
        # combine db_generator_explicit and db_generator_generic into one
        # generator, where ruby types are used if they are accurate. If there
        # is no accurate ruby type, we use the explicit database type. This
        # gives us cleaner column dumps, as ruby types have a better, more
        # generic interface (e.g. `String :col_name` as opposed to
        # `column :col_name, 'varchar(255)`).
        
        # start with db_generator_generic, and correct as need be
        db_generator = db_generator_generic.dup

        # avoid using Sequel::Model.db_schema because it has odd caching
        # behavior across classes that breaks tests
        db.schema(table_name).each do |name, col_schema|
          type_hash = db.column_schema_to_ruby_type(col_schema)

          # We know there's no corresponding ruby type if:
          #   type_hash == {:type => String}
          # In this case, copy over the column from db_generator_explicit.
          if type_hash.length == 1 && type_hash[:type] == String
            index = db_generator.columns.find_index {|c| c[:name] == name}
            col = db_generator_explicit.columns.find {|c| c[:name] == name}
            db_generator.columns[index] = col
          end
        end

        db_generator
      end

      # Check if all database columns match the expected columns.
      def check_all_columns(db_generator, exp_generator)
        db_columns_hash = Hash[db_generator.columns.map {|c| [c[:name], c]}]
        exp_columns_hash = Hash[exp_generator.columns.map {|c| [c[:name], c]}]
        schema_diffs = []

        extra_col_names = db_columns_hash.keys - exp_columns_hash.keys
        extra_col_names.each do |col_name|
          schema_diffs << {:type => SchemaError::COL_EXTRA,
                           :generator => db_generator,
                           :col_name => col_name}
        end

        missing_col_names = exp_columns_hash.keys - db_columns_hash.keys
        missing_col_names.each do |col_name|
          schema_diffs << {:type => SchemaError::COL_MISSING,
                           :generator => exp_generator,
                           :col_name => col_name}
        end

        db_columns_hash.each do |key, db_col|
          exp_col = exp_columns_hash[key]
          next if !exp_col

          col_diff = check_col(db_generator, db_col, exp_generator, exp_col)
          schema_diffs << col_diff if col_diff
        end

        if schema_diffs.length > 0
          raise SchemaError.new(table_name, schema_diffs)
        end
      end

      # Check if the given database column matches the expected column.
      def check_col(db_generator, db_col, exp_generator, exp_col)
        # db_col is guaranteed to be valid, so we just check exp_col for extra keys
        invalid_keys = exp_col.keys - DEFAULT_COL_OPTS.keys
        message = "#{invalid_keys.join(', ')} are invalid options for column " +
                  "#{exp_col[:name]}"
        fail KeyError, message if invalid_keys.length > 0

        db_col = DEFAULT_COL_OPTS.merge(db_col)
        exp_col = DEFAULT_COL_OPTS.merge(exp_col)

        type_literal = db.method(:type_literal)
        # already accounted for in type check
        keys_accounted_for = [:text, :fixed, :size, :serial]

        # db_col and exp_col now have the same keys; compare then
        match = db_col.all? do |key, value|
          if key == :type
            # types could either be strings or ruby types; normalize them
            type_literal.call(db_col).to_s == type_literal.call(exp_col).to_s
          elsif keys_accounted_for.include?(key)
            true
          else
            value == exp_col[key]
          end
        end

        if !match
          require 'awesome_print'
          # ap db_col
          # ap type_literal.call(db_col)
          # ap exp_col
          # ap type_literal.call(exp_col)
        end
        match ? nil : {:type => SchemaError::COL_MISMATCH,
                       :db_generator => db_generator,
                       :exp_generator => exp_generator,
                       :col_name => db_col[:name]}
      end
    end
  end
end
