module ModelSchema
  # ENV variable name to disable schema checks.
  DISABLE_MODEL_SCHEMA_KEY = 'DISABLE_MODEL_SCHEMA'

  # field types representing table columns and table indexes
  FIELD_COLUMNS = :columns
  FIELD_INDEXES = :indexes
  FIELDS = [FIELD_COLUMNS, FIELD_INDEXES]

  # default column parameters
  DEFAULT_COL = {
    :name => nil,
    :type => nil,
    :collate => nil,
    :default => nil,
    :deferrable => nil,
    :index => nil,
    :key => [:id],
    :null => nil,
    :on_delete => :no_action,
    :on_update => :no_action,
    :primary_key => nil,
    :primary_key_constraint_name => nil,
    :unique => nil,
    :unique_constraint_name => nil,
    :serial => nil,
    :table => nil,
    :text => nil,
    :fixed => nil,
    :size => nil,
    :only_time => nil,
  }

  # default index parameters
  DEFAULT_INDEX = {
    :columns => nil,
    :name => nil,
    :type => nil,
    :unique => nil,
    :where => nil,
  }
end
