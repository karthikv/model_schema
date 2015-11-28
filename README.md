# ModelSchema
ModelSchema lets you annotate a
[Sequel](https://github.com/jeremyevans/sequel/) Model with its expected schema
(columns/indexes). Instead of seeing a Sequel Model file that looks like this:

```rb
class User < Sequel::Model(:users)
end
```

You'll see one that looks like this:

```rb
class User < Sequel::Model(:users)
  model_schema do
    primary_key :id

    String :email, :null => false
    String :password, :null => false

    TrueClass :is_admin, :default => false

    DateTime :created_at, :null => false
    DateTime :updated_at

    index :email
  end
end
```

Unlike other similar gems, ModelSchema provides *enforcement*; if the schema you
specify doesn't match the table schema, ModelSchema will raise an error and
tell you exactly what's wrong, like so:

```
ModelSchema::SchemaError: Table users does not match the expected schema.

Table users has extra columns:

  Integer :age

Table users is missing columns:

  TrueClass :is_admin, :default => false

Table users has mismatched indexes:

  actual:    index [:email], :unique => true
  expected:  index [:email]

You may disable schema checks by passing :disable => true to model_schema or by
setting the ENV variable DISABLE_MODEL_SCHEMA=1.
```

When developing on a team, local databases of team members can easily get out
of sync due to differing migrations. ModelSchema immediately lets you know if
the schema you expect differs from the actual schema. This ensures you identify
database inconsistencies before they cause problems. As a nice added benefit,
ModelSchema lets you see a list of columns for a model directly within the
class itself.

## Installation
Add `model_schema` to your Gemfile:

```rb
gem 'model_schema'
```

And then execute `bundle` in your terminal. You can also install `model_schema`
with `gem` directly by running `gem install model_schema`.

## Usage
Require `model_schema` and register the plugin with Sequel:

```rb
require 'model_schema'
Sequel.plugin(ModelSchema::Plugin)
```

Then, in each model where you'd like to use ModelSchema, introduce a call to
`model_schema`, passing in a block that defines the schema. The block operates
exactly as a [Sequel `create_table`
block](http://sequel.jeremyevans.net/rdoc/files/doc/schema_modification_rdoc.html).
See the documentation on that page for further details.

```rb
class Post < Sequel::Model(:posts)
  model_schema do
    primary_key :id

    String :title, :null => false
    String :description, :text => true, :null => false
    DateTime :date_posted, :null => false
  end
end
```

When the class is loaded, ModelSchema will ensure the table schema matches the
given schema. If there are any errors, it will raise
a `ModelSchema::SchemaError`, notifying you of any inconsistencies.

You may pass an optional hash to `model_schema` with the following options:

`disable`: `true` to disable all schema checks, `false` otherwise
`no_indexes`: `true` to disable schema checks for indexes (columns will still
be checked), `false` otherwise

For instance, to disable index checking:

```rb
class Item < Sequel::Model(:items)
  model_schema(:no_indexes => true) do
    ...
  end
end
```

Note that you can disable ModelSchema in two ways: either pass `:disable =>
true` to the `model_schema` method, or set the environment variable
`DISABLE_MODEL_SCHEMA=1` .

## Limitations
ModelSchema has a few notable limitations:

- It checks columns independently from indexes. Say you create a table like so:

  ```rb
  DB.create_table(:items) do
    String :name, :unique => true
    Integer :value, :index => true
  end
  ```

  The corresponding `model_schema` block would be:

  ```rb
  class Item < Sequel::Model(:items)
    model_schema do
      String :name
      Integer :value

      index :name, :unique => true
      index :value
    end
  end
  ```

  We have to separate the columns from the indexes, since the schema dumper
  reads them independently of one another.

- It relies on Sequel's [schema dumper extension](http://sequel.jeremyevans.net/rdoc/files/doc/migration_rdoc.html#label-Dumping+the+current+schema+as+a+migration)
  to read your table's schema. The schema dumper doesn't read constraints,
  triggers, special index types (e.g. gin, gist) or partial indexes; you'll
  have to omit these from your `model_schema` block.

- It doesn't handle all type aliasing. For instance, the Postgres types
  `character varying(255)[]` and `varchar(255)[]` are equivalent, but
  ModelSchema is unaware of this. In turn, you might see this error message:

  ```
  Table complex has mismatched columns:

    actual:    column :advisors, "character varying(255)[]", :null=>false
    expected:  column :advisors, "varchar(255)[]", :null=>false
  ```

  In the above case, you'll need to change `varchar(255)[]` to `character
  varying(255)[]` in your `model_schema` block to fix the issue.

  A similar problem occurs with `numeric(x, 0)` and `numeric(x)`, where x is an
  integer; they are equivalent in Postgres, but ModelSchema doesn't know this.

## Development and Contributing
After cloning this repository, execute `bundle` to install dependencies. You
may run tests with `rake test`, and open up a REPL using `bin/repl`.

To install this gem onto your local machine, run `bundle exec rake install`.

Any bug reports and pull requests are welcome.

## License
See the [LICENSE.txt](blob/master/LICENSE.txt) file.