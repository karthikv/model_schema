require 'sequel'

module ModelSchema
  module Plugin
    module ClassMethods
      def model_schema(options={}, &block)
        db.extension(:schema_dumper)

        db_generator = table_generator
        exp_generator = db.create_table_generator(&block)
        
        # TODO: remove default_elem?

        check_all(FIELD_COLUMNS, :db_generator => db_generator,
                                 :exp_generator => exp_generator,
                                 :default_elem => DEFAULT_COL)
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

      # Check if db_generator.[attr_name] matches exp_generator.[attr_name],
      # where attr_name is either columns, constraints, or indexes.
      #
      # field: what to check: :columns, :constraints, or :indexes
      # opts:
      #   :db_generator => db table generator
      #   :exp_generator => expected table generator
      #   :default_elem => default column, constraint, or index element
      def check_all(field, opts)
        db_generator, exp_generator = opts.values_at(:db_generator, :exp_generator)
        default_elem = opts[:default_elem]

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
                                :exp_elem => exp_elem,
                                :default_elem => default_elem)
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
                                                :exp_elem => exp_elem,
                                                :default_elem => default_elem)
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

        raise SchemaError.new(table_name, schema_diffs) if schema_diffs.length > 0
      end

      # Returns the index of an element in db_array that closely matches exp_elem.
      def find_close_match(field, exp_elem, db_array)
        attr = case field
               when FIELD_COLUMNS
                 :name
               when FIELD_INDEXES
                 :columns
               when FIELD_CONSTRAINTS
                 :check
               end
        db_array.find_index {|e| e[attr] == exp_elem[attr]}
      end

      # Check if the given database element matches the expected element.
      #
      # field: what to check: :columns, :constraints, or :indexes
      # opts:
      #   :db_generator => db table generator
      #   :exp_generator => expected table generator
      #   :db_elem => column, constraint, or index from db_generator
      #   :exp_elem => column, constraint, or index from exp_generator
      #   :default_elem => default column, constraint, or index element
      def check_single(field, opts)
        db_generator, exp_generator = opts.values_at(:db_generator, :exp_generator)
        db_original_elem, exp_original_elem = opts.values_at(:db_elem, :exp_elem)
        default_elem = opts[:default_elem]

        db_elem = default_elem.merge(db_original_elem)
        exp_elem = default_elem.merge(exp_original_elem)

        error = {:field => field,
                 :type => SchemaError::TYPE_MISMATCH,
                 :db_generator => db_generator,
                 :exp_generator => exp_generator,
                 :db_elem => db_original_elem,
                 :exp_elem => exp_original_elem}
        return error if db_elem.length != exp_elem.length

        # db_elem and exp_elem now have the same keys; compare then
        case field
        when :columns
          type_literal = db.method(:type_literal)
          # already accounted for in type check
          keys_accounted_for = [:text, :fixed, :size, :serial]

          match = db_elem.all? do |key, value|
            if key == :type
              # types could either be strings or ruby types; normalize them
              type_literal.call(db_elem).to_s == type_literal.call(exp_elem).to_s
            elsif keys_accounted_for.include?(key)
              true
            else
              value == exp_elem[key]
            end
          end

        when :indexes
        when :constraints
          match = db_elem.all? {|key, value| value == exp_elem[key]}
        end

        match ? nil : error
      end
    end
  end
end
