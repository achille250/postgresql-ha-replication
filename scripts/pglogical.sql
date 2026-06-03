sudo apt-get install postgresql-15-pglogical

1. On Primary

-- Enable pglogical
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create provider node
SELECT pglogical.create_node(
  node_name := 'primary_node',
  dsn := 'host=CHANGE_ME_HOST dbname=source_db user=replica password=CHANGE_ME'
);

-- Add all tables in the public schema to the default replication set
SELECT pglogical.replication_set_add_all_tables('default', ARRAY['public']);

2. On Replica1

Connect to source_db and run

-- Enable pglogical
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create node on this instance
SELECT pglogical.create_node(
  node_name := 'replica1_node',
  dsn := 'host=CHANGE_ME_HOST dbname=source_db user=replica password=CHANGE_ME'
);

-- Subscribe to Primary
SELECT pglogical.create_subscription(
  subscription_name := 'sub_from_primary',
  provider_dsn := 'host=CHANGE_ME_HOST dbname=source_db user=replica password=CHANGE_ME'
);

3. On Replica2

Connect to source_db and run

-- Enable pglogical
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create node
SELECT pglogical.create_node(
  node_name := 'replica2_node',
  dsn := 'host=CHANGE_ME_HOST dbname=source_db user=replica password=CHANGE_ME'
);

-- Subscribe to Replica1
SELECT pglogical.create_subscription(
  subscription_name := 'sub_from_replica1',
  provider_dsn := 'host=CHANGE_ME_HOST dbname=source_db user=replica password=CHANGE_ME'
);



SELECT pglogical.create_node(
  node_name := 'subscriber_node',
  dsn := 'host=CHANGE_ME_HOST port=5433 dbname=dsacco_bnr user=pglogical password=CHANGE_ME'
);

SELECT pglogical.create_subscription(
  subscription_name := 'cdc_subscription',
  provider_dsn := 'host=CHANGE_ME_HOST port=5432 dbname=dsaccokigali_db user=pglogical password=CHANGE_ME',
  replication_sets := ARRAY['default']
);

host    replication     pglogical         CHANGE_ME_HOST/32           trust


SELECT pglogical.create_node(
  node_name := 'bnr_subscriber',
  dsn := 'host=CHANGE_ME_HOST port=5433 dbname=dsacco_bnr user=pglogical password=CHANGE_ME'
);




SELECT pglogical.create_subscription(
  subscription_name := 'cdc_subscription',
  provider_dsn := 'host=CHANGE_ME_HOST port=5432 dbname=dsaccokigali_db user=pglogical password=CHANGE_ME',
  replication_sets := ARRAY['default','insert_only'],
  synchronize_structure := false,
  synchronize_data := false
);
