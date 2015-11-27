require 'test_helper'

class SchemaErrorTest < BaseTest
  def setup
    @db = Sequel::Database.new
    @db.extension(:schema_dumper)
    @table_name = 'schema_error_table'
  end

  def create_table_generator
    Sequel::Schema::CreateTableGenerator.new(@db) do
      primary_key :id
      foreign_key :organization_id, :organizations, :null => false, 
                                                    :key => [:id],
                                                    :on_delete => :cascade

      Integer :type
      String :first_name, :text => true, :null => false
      column :emails, 'text[]', :null => false
      DateTime :created_at, :null => false
      DateTime :updated_at
    end
  end

  def dump_column(generator, name)
    instance.dump_single(field_columns, generator,
                         find_match(generator.columns, :name => name))
  end

  def test_dump_single_column
    generator = create_table_generator
    assert_equal 'Integer :type', dump_column(generator, :type)
  end

  def test_dump_single_column_with_options
    generator = create_table_generator
    assert_equal 'String :first_name, :text=>true, :null=>false',
                 dump_column(generator, :first_name)
  end

  def test_dump_single_foreign_key
    generator = create_table_generator
    fk_str = %(foreign_key :organization_id, :organizations, :null=>false, 
               :key=>[:id], :on_delete=>:cascade).gsub(/\n\s+/, '')
    assert_equal fk_str, dump_column(generator, :organization_id)
  end

  def test_dump_single_primary_key
    generator = create_table_generator
    assert_equal 'primary_key :id', dump_column(generator, :id)
  end

  def test_dump_single_custom_type
    generator = create_table_generator
    assert_equal 'column :emails, "text[]", :null=>false',
                 dump_column(generator, :emails)
  end

  def instance(schema_diffs=[])
    ModelSchema::SchemaError.new(@table_name, schema_diffs)
  end

  def test_col_extra
    generator = create_table_generator
    schema_diffs = [create_extra_diff(field_columns, generator, :name => :created_at),
                    create_extra_diff(field_columns, generator, :name => :first_name)]
    message = instance(schema_diffs).to_s

    assert_includes message, @table_name
    assert_includes message, 'extra columns'
    assert_includes message, dump_column(generator, :created_at)
    assert_includes message, dump_column(generator, :first_name)
  end

  def test_col_missing
    generator = create_table_generator
    schema_diffs = [create_missing_diff(field_columns, generator, :name => :type),
                    create_missing_diff(field_columns, generator, :name => :updated_at)]
    message = instance(schema_diffs).to_s

    assert_includes message, @table_name
    assert_includes message, 'missing columns'
    assert_includes message, dump_column(generator, :type)
    assert_includes message, dump_column(generator, :updated_at)
  end

  def create_exp_table_generator
    Sequel::Schema::CreateTableGenerator.new(@db) do
      foreign_key :organization_id, :org
      String :emails, :text => true, :null => false, :unique => true
      DateTime :created_at
    end
  end

  def test_col_mismatch
    generator = create_table_generator
    exp_generator = create_exp_table_generator

    schema_diffs = [create_mismatch_diff(field_columns, generator, exp_generator,
                                         :name => :organization_id),
                    create_mismatch_diff(field_columns, generator, exp_generator,
                                         :name => :emails)]
    message = instance(schema_diffs).to_s

    assert_includes message, @table_name
    assert_includes message, 'mismatched columns'

    assert_includes message, dump_column(generator, :organization_id)
    assert_includes message, dump_column(exp_generator, :organization_id)
    assert_includes message, dump_column(generator, :emails)
    assert_includes message, dump_column(exp_generator, :emails)
  end

  def test_col_all
    generator = create_table_generator
    exp_generator = create_exp_table_generator

    schema_diffs = [create_extra_diff(field_columns, generator, :name => :type),
                    create_missing_diff(field_columns, generator, :name => :id),
                    create_missing_diff(field_columns, generator, :name => :first_name),
                    create_mismatch_diff(field_columns, generator, exp_generator,
                                         :name => :created_at)]
    message = instance(schema_diffs).to_s

    assert_includes message, @table_name
    assert_includes message, 'extra columns'
    assert_includes message, dump_column(generator, :type)

    assert_includes message, 'missing columns'
    assert_includes message, dump_column(generator, :id)
    assert_includes message, dump_column(generator, :first_name)

    assert_includes message, 'mismatched columns'
    assert_includes message, dump_column(generator, :created_at)
    assert_includes message, dump_column(exp_generator, :created_at)
  end
end
