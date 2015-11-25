require 'test_helper'

class ModelSchemaTest < BaseTest
  include Minitest::Hooks

  def before_all
    Sequel::Model.plugin(ModelSchema)
    @db = Sequel.connect(ENV['DB_URL'])
    @db.cache_schema = false
  end

  def around
    @db.transaction(:rollback => :always, :auto_savepoint => true) {super}
  end

  def test_version
    refute_nil ModelSchema::VERSION
  end

  def create_simple
    @table_name = :simple
    @db.create_table(@table_name) do
      String :name
    end
  end

  def test_simple_schema
    create_simple

    Class.new(Sequel::Model(@table_name)) do
      model_schema do
        String :name
      end
    end
  end

  def test_simple_schema_extra_col
    create_simple

    begin
      Class.new(Sequel::Model(@table_name)) do
        model_schema {}
      end
    rescue ModelSchema::SchemaError => error
      assert_includes error.message, 'extra columns'
      assert_includes error.message, 'String :name'
    else
      flunk 'Extra column not detected'
    end
  end

  def test_simple_schema_missing_col
    create_simple

    begin
      Class.new(Sequel::Model(@table_name)) do
        model_schema do
          String :name
          Integer :age
        end
      end
    rescue ModelSchema::SchemaError => error
      assert_includes error.message, 'missing columns'
      assert_includes error.message, 'Integer :age'
    else
      flunk 'Missing column not detected'
    end
  end

  def create_complex
    @table_name = :simple
    @db.create_table(:others) do
      primary_key :id
      Integer :value
    end

    @db.create_table(@table_name) do
      primary_key :id
      foreign_key :other_id, :others, :null => false, :on_delete => :cascade

      String :name, :null => false
      String :legal_name
      String :type
      String :location

      column :advisors, 'character varying(255)[]', :null => false
      column :interests, 'text[]', :null => false

      Time :created_at, :null => false
      Time :updated_at

      unique [:other_id, :name]
    end
  end

  def test_complex_schema
    create_complex

    Class.new(Sequel::Model(@table_name)) do
      model_schema do
        primary_key :id
        foreign_key :other_id, :others, :null => false, :on_delete => :cascade

        String :name, :null => false
        String :legal_name
        String :type
        String :location

        column :advisors, 'character varying(255)[]', :null => false
        column :interests, 'text[]', :null => false

        Time :created_at, :null => false
        Time :updated_at

        unique [:other_id, :name]
      end
    end
  end
end
