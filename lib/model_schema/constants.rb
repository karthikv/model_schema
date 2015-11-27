module ModelSchema
  FIELD_COLUMNS = :columns
  FIELD_INDEXES = :indexes
  FIELD_CONSTRAINTS = :constraints
  FIELDS = [FIELD_COLUMNS, FIELD_INDEXES, FIELD_CONSTRAINTS]

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
end
