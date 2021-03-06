require 'sequel'

module ModelSchema
  # Allows you to define an expected schema for a Sequel::Model class and fail
  # if that schema is not met.
  module Plugin
    module ClassMethods
      # Checks if the model's table schema matches the schema specified by the
      # given block. Raises a SchemaError if this isn't the case.
      #
      # options:
      # :disable => true to disable schema checks;
      #             you may also set the ENV variable DISABLE_MODEL_SCHEMA=1
      # :no_indexes => true to disable index checks
      def model_schema(options={}, &block)
        return if ENV[DISABLE_MODEL_SCHEMA_KEY] == '1' || options[:disable]
        db.extension(:schema_dumper)

        # table generators are Sequel's way of representing schemas
        db_generator = table_generator
        exp_generator = db.create_table_generator(&block)
        
        schema_errors = check_all(FIELD_COLUMNS, db_generator, exp_generator)
        if !options[:no_indexes]
          schema_errors += check_all(FIELD_INDEXES, db_generator, exp_generator)
        end
        
        raise SchemaError.new(table_name, schema_errors) if schema_errors.length > 0
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

          if type_hash == {:type => String}
            # There's no corresponding ruby type, as per:
            # <https://github.com/jeremyevans/sequel/blob/a2cfbb9/lib/sequel/
            #  extensions/schema_dumper.rb#L59-L61>
            # Copy over the column from db_generator_explicit.
            index = db_generator.columns.find_index {|c| c[:name] == name}
            col = db_generator_explicit.columns.find {|c| c[:name] == name}
            db_generator.columns[index] = col
          end
        end

        db_generator
      end

      # Check if db_generator and exp_generator match for the given field
      # (FIELD_COLUMNS for columns or FIELD_INDEXES for indexes).
      def check_all(field, db_generator, exp_generator)
        # To find an accurate diff, we perform two passes on exp_array. In the
        # first pass, we find perfect matches between exp_array and db_array,
        # deleting the corresponding elements. In the second pass, for each
        # exp_elem in exp_array, we find the closest db_elem in db_array that
        # matches it. We then add a mismatch diff between db_elem and exp_elem
        # and remove db_elem from db_array. If no db_elem is deemed close
        # enough, we add a missing diff for exp_elem. Finally, we add an extra
        # diff for each remaining db_elem in db_array.

        # don't modify original arrays
        db_array = db_generator.send(field).dup
        exp_array = exp_generator.send(field).dup

        # first pass: remove perfect matches
        exp_array.select! do |exp_elem|
          diffs = db_array.map do |db_elem|
            check_single(field, :db_generator => db_generator,
                                :exp_generator => exp_generator,
                                :db_elem => db_elem,
                                :exp_elem => exp_elem)
          end

          index = diffs.find_index(nil)
          if index
            # found perfect match; delete elem so it won't be matched again
            db_array.delete_at(index)
            false  # we've accounted for this element
          else
            true  # we still need to account for this element
          end
        end

        schema_diffs = []

        # second pass: find diffs
        exp_array.each do |exp_elem|
          index = find_close_match(field, exp_elem, db_array)

          if index
            # add mismatch diff between exp_elem and db_array[index]
            schema_diffs << check_single(field, :db_generator => db_generator,
                                                :exp_generator => exp_generator,
                                                :db_elem => db_array[index],
                                                :exp_elem => exp_elem)
            db_array.delete_at(index)
          else
            # add missing diff, since no db_elem is deemed close enough
            schema_diffs << {:field => field,
                             :type => SchemaError::TYPE_MISSING,
                             :generator => exp_generator,
                             :elem => exp_elem}
          end
        end

        # because we deleted as we went on, db_array holds extra elements
        db_array.each do |db_elem|
          schema_diffs << {:field => field,
                           :type => SchemaError::TYPE_EXTRA,
                           :generator => db_generator,
                           :elem => db_elem}
        end

        schema_diffs
      end

      # Returns the index of an element in db_array that closely matches exp_elem,
      # or nil if no such element exists.
      def find_close_match(field, exp_elem, db_array)
        case field
        when FIELD_COLUMNS
          db_array.find_index {|e| e[:name] == exp_elem[:name]}
        when FIELD_INDEXES
          db_array.find_index do |e|
            e[:name] == exp_elem[:name] || e[:columns] == exp_elem[:columns]
          end
        end
      end

      # Check if the given database element matches the expected element.
      #
      # field: FIELD_COLUMNS for columns or FIELD_INDEXES for indexes
      # opts:
      #   :db_generator => db table generator
      #   :exp_generator => expected table generator
      #   :db_elem => column, constraint, or index from db_generator
      #   :exp_elem => column, constraint, or index from exp_generator
      def check_single(field, opts)
        db_generator, exp_generator = opts.values_at(:db_generator, :exp_generator)
        db_elem, exp_elem = opts.values_at(:db_elem, :exp_elem)

        error = {:field => field,
                 :type => SchemaError::TYPE_MISMATCH,
                 :db_generator => db_generator,
                 :exp_generator => exp_generator,
                 :db_elem => db_elem,
                 :exp_elem => exp_elem}

        # db_elem and exp_elem now have the same keys; compare then
        case field
        when FIELD_COLUMNS
          db_elem_defaults = DEFAULT_COL.merge(db_elem)
          exp_elem_defaults = DEFAULT_COL.merge(exp_elem)
          return error if db_elem_defaults.length != exp_elem_defaults.length

          type_literal = db.method(:type_literal)
          # already accounted for in type check
          keys_accounted_for = [:text, :fixed, :size, :serial]

          match = db_elem_defaults.all? do |key, value|
            if key == :type
              # types could either be strings or ruby types; normalize them
              db_type = type_literal.call(db_elem_defaults).to_s
              exp_type = type_literal.call(exp_elem_defaults).to_s
              db_type == exp_type
            elsif keys_accounted_for.include?(key)
              true
            else
              value == exp_elem_defaults[key]
            end
          end

        when FIELD_INDEXES
          db_elem_defaults = DEFAULT_INDEX.merge(db_elem)
          exp_elem_defaults = DEFAULT_INDEX.merge(exp_elem)
          return error if db_elem_defaults.length != exp_elem_defaults.length

          # if no index name is specified, accept any name
          db_elem_defaults.delete(:name) if !exp_elem_defaults[:name]
          match = db_elem_defaults.all? {|key, value| value == exp_elem_defaults[key]}
        end

        match ? nil : error
      end
    end
  end
end
