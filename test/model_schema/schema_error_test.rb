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

  def test_dump_col
    generator = create_table_generator
    assert_equal 'Integer :type', instance.dump_col(generator, :type)
  end

  def test_dump_col_with_options
    generator = create_table_generator
    assert_equal 'String :first_name, :text=>true, :null=>false',
                 instance.dump_col(generator, :first_name)
  end

  def test_dump_col_foreign_key
    generator = create_table_generator
    fk_str = %(foreign_key :organization_id, :organizations, :null=>false, 
               :key=>[:id], :on_delete=>:cascade).gsub(/\n\s+/, '')
    assert_equal fk_str, instance.dump_col(generator, :organization_id)
  end

  def test_dump_col_primary_key
    generator = create_table_generator
    assert_equal 'primary_key :id', instance.dump_col(generator, :id)
  end

  def test_dump_col_custom_type
    generator = create_table_generator
    assert_equal 'column :emails, "text[]", :null=>false',
                 instance.dump_col(generator, :emails)
  end

  def instance(schema_diffs=[])
    ModelSchema::SchemaError.new(@table_name, schema_diffs)
  end

  def test_col_extra
    generator = create_table_generator
    schema_diffs = [{:type => ModelSchema::SchemaError::COL_EXTRA,
                     :generator => generator,
                     :col_name => :created_at},
                    {:type => ModelSchema::SchemaError::COL_EXTRA,
                     :generator => generator,
                     :col_name => :first_name}]
    error = instance(schema_diffs)
    message = error.to_s

    assert_includes message, @table_name
    assert_includes message, 'extra columns'
    assert_includes message, error.dump_col(generator, :created_at)
    assert_includes message, error.dump_col(generator, :first_name)
  end

  def test_col_missing
    generator = create_table_generator
    schema_diffs = [{:type => ModelSchema::SchemaError::COL_MISSING,
                     :generator => generator,
                     :col_name => :type},
                    {:type => ModelSchema::SchemaError::COL_MISSING,
                     :generator => generator,
                     :col_name => :updated_at}]
    error = instance(schema_diffs)
    message = error.to_s

    assert_includes message, @table_name
    assert_includes message, 'missing columns'
    assert_includes message, error.dump_col(generator, :type)
    assert_includes message, error.dump_col(generator, :updated_at)
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

    schema_diffs = [{:type => ModelSchema::SchemaError::COL_MISMATCH,
                     :db_generator => generator,
                     :exp_generator => exp_generator,
                     :col_name => :organization_id},
                    {:type => ModelSchema::SchemaError::COL_MISMATCH,
                     :db_generator => generator,
                     :exp_generator => exp_generator,
                     :col_name => :emails}]
    error = instance(schema_diffs)
    message = error.to_s

    assert_includes message, @table_name
    assert_includes message, 'mismatched columns'

    assert_includes message, error.dump_col(generator, :organization_id)
    assert_includes message, error.dump_col(exp_generator, :organization_id)
    assert_includes message, error.dump_col(generator, :emails)
    assert_includes message, error.dump_col(exp_generator, :emails)
  end

  def test_col_all
    generator = create_table_generator
    exp_generator = create_exp_table_generator

    schema_diffs = [{:type => ModelSchema::SchemaError::COL_EXTRA,
                     :generator => generator,
                     :col_name => :type},
                    {:type => ModelSchema::SchemaError::COL_MISSING,
                     :generator => generator,
                     :col_name => :id},
                    {:type => ModelSchema::SchemaError::COL_MISSING,
                     :generator => generator,
                     :col_name => :first_name},
                    {:type => ModelSchema::SchemaError::COL_MISMATCH,
                     :db_generator => generator,
                     :exp_generator => exp_generator,
                     :col_name => :created_at}]
    error = instance(schema_diffs)
    message = error.to_s

    assert_includes message, @table_name
    assert_includes message, 'extra columns'
    assert_includes message, error.dump_col(generator, :type)

    assert_includes message, 'missing columns'
    assert_includes message, error.dump_col(generator, :id)
    assert_includes message, error.dump_col(generator, :first_name)

    assert_includes message, 'mismatched columns'
    assert_includes message, error.dump_col(generator, :created_at)
    assert_includes message, error.dump_col(exp_generator, :created_at)
  end
end
