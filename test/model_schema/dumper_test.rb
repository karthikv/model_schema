require 'test_helper'

class DumperTest < BaseTest
  def before_all
    @db_url = ENV['DB_URL']
    @db = Sequel::Database.connect(@db_url)
  end

  def around
    @db.transaction(:rollback => :always, :auto_savepoint => true) {super}
  end

  def dumper
    ModelSchema::Dumper
  end

  def with_captured_stderr
    begin
      old_stderr = $stderr
      $stderr = StringIO.new('', 'w')
      yield
      $stderr.string
    ensure
      $stderr = old_stderr
    end
  end

  def test_no_model
    error = nil
    stderr = with_captured_stderr do
      begin
        dumper.run(['-c', @db_url])
      rescue SystemExit => e
        error = e
      end
    end

    refute_nil error
    assert_includes stderr, 'provide at least one model file'
  end

  def test_no_connection
    error = nil
    stderr = with_captured_stderr do
      begin
        dumper.run(['some-model-file'])
      rescue SystemExit => e
        error = e
      end
    end

    refute_nil error
    assert_includes stderr, 'provide a connection'
  end

  def write_model(table_name)
    path = "model_schema/#{table_name}"
    contents = ['# A simple model for a simple table',
                'module SomeApp',
                '  module Models',
                "    class Item < Sequel::Model(:#{table_name})",
                '      belongs_to :other, :class => :Other',
                '    end',
                '  end',
                'end'].join("\n")
    File.stubs(:read).with(path).returns(contents)
    path
  end

  def expected_simple_model(table_name, tab)
    ['# A simple model for a simple table',
     'module SomeApp',
     '  module Models',
     "    class Item < Sequel::Model(:#{table_name})",
     "    #{tab}model_schema do",
     "    #{tab * 2}String :name, :size => 50",
     "    #{tab * 2}Integer :value, :null => false",
     '',
     "    #{tab * 2}index [:name], :unique => true",
     "    #{tab}end",
     '      belongs_to :other, :class => :Other',
     '    end',
     '  end',
     'end'].join("\n")
  end

  def expected_complex_model(table_name)
    ['# A simple model for a simple table',
     'module SomeApp',
     '  module Models',
     "    class Item < Sequel::Model(:#{table_name})",
     "      model_schema do",
     "        primary_key :id",
     "        foreign_key :other_id, :others, :null => false, :key => [:id], :on_delete => :cascade",
     "        String :name, :text => true",
     "        String :location, :size => 50, :fixed => true",
     "        String :legal_name, :size => 200",
     "        String :advisor, :text => true",
     "        BigDecimal :amount, :size => [10, 0]",
     "        Integer :value, :null => false",
     "        column :advisors, \"character varying(255)[]\", :null => false",
     "        column :interests, \"text[]\", :null => false",
     "        TrueClass :is_right",
     "        DateTime :created_at, :null => false",
     "        Time :updated_at, :only_time => true",
     '',
     "        index [:other_id, :name]",
     "        index [:value], :name => :complex_value_key, :unique => true",
     "        index [:interests], :name => :int_index",
     "      end",
     '      belongs_to :other, :class => :Other',
     '    end',
     '  end',
     'end'].join("\n")
  end

  def set_up_dump_simple(tab)
    simple_table = create_simple_table(@db)
    path = write_model(simple_table)
    contents = expected_simple_model(simple_table, tab)

    Sequel.stubs(:connect).with(@db_url).returns(@db)
    File.expects(:write).with do |p, c|
      assert_equal path, p
      assert_equal contents, c
      true
    end
    
    path
  end

  def test_dump_simple
    path = set_up_dump_simple('  ')
    dumper.run(['-c', @db_url, path])
  end

  def test_dump_simple_four_spaces
    path = set_up_dump_simple('    ')
    dumper.run(['-c', @db_url, '-t', '4', path])
  end

  def test_dump_simple_hard_tab
    path = set_up_dump_simple("\t")
    dumper.run(['-c', @db_url, '-t', '0', path])
  end

  def test_dump_complex
    complex_table = create_complex_table(@db)
    path = write_model(complex_table)
    contents = expected_complex_model(complex_table)

    Sequel.stubs(:connect).with(@db_url).returns(@db)
    File.expects(:write).with do |p, c|
      assert_equal path, p
      assert_equal contents, c
      true
    end

    dumper.run(['-c', @db_url, path])
  end

  def test_dump_multiple
    simple_table = create_simple_table(@db)
    complex_table = create_complex_table(@db)

    simple_path = write_model(simple_table)
    complex_path = write_model(complex_table)

    simple_contents = expected_simple_model(simple_table, '  ')
    complex_contents = expected_complex_model(complex_table)

    Sequel.stubs(:connect).with(@db_url).returns(@db)
    File.expects(:write).with(simple_path, simple_contents)
    File.expects(:write).with(complex_path, complex_contents)

    dumper.run(['-c', @db_url, simple_path, complex_path])
  end

  def test_dump_multiple_abort_error
    path = set_up_dump_simple('  ')
    other_path = 'model_schema/other_path'
    File.stubs(:read).with(other_path).returns("Some bogus\n\tmodel\n\tfile")

    error = nil
    stderr = with_captured_stderr do
      begin
        dumper.run(['-c', @db_url, other_path, path])
      rescue SystemExit => e
        error = e
      end
    end

    refute_nil error
    assert_includes stderr, "couldn't find class that extends Sequel::Model"
  end

  def test_dump_multiple_standard_error
    path = set_up_dump_simple('  ')
    other_path = 'model_schema/non_existent_path'
    File.stubs(:read).with(other_path).raises(Errno::ENOENT)

    error = nil
    stderr = with_captured_stderr do
      begin
        dumper.run(['-c', @db_url, other_path, path])
      rescue SystemExit => e
        error = e
      end
    end

    refute_nil error
    assert_includes stderr, "No such file"
  end
end
