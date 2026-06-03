sudo apt-get install postgresql-15-pglogical

1. On Primary

-- Enable pglogical
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create provider node
SELECT pglogical.create_node(
  node_name := 'primary_node',
  dsn := 'host=10.20.1.250 dbname=source_db user=replica password=your_password'
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
  dsn := 'host=10.20.1.251 dbname=source_db user=replica password=your_password'
);

-- Subscribe to Primary
SELECT pglogical.create_subscription(
  subscription_name := 'sub_from_primary',
  provider_dsn := 'host=10.20.1.250 dbname=source_db user=replica password=your_password'
);

3. On Replica2

Connect to source_db and run

-- Enable pglogical
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create node
SELECT pglogical.create_node(
  node_name := 'replica2_node',
  dsn := 'host=10.20.1.252 dbname=source_db user=replica password=your_password'
);

-- Subscribe to Replica1
SELECT pglogical.create_subscription(
  subscription_name := 'sub_from_replica1',
  provider_dsn := 'host=10.20.1.251 dbname=source_db user=replica password=your_password'
);



SELECT pglogical.create_node(
  node_name := 'subscriber_node',
  dsn := 'host=10.50.4.10 port=5433 dbname=dsacco_bnr user=pglogical password=pglogical'
);

SELECT pglogical.create_subscription(
  subscription_name := 'cdc_subscription',
  provider_dsn := 'host=10.50.4.12 port=5432 dbname=dsaccokigali_db user=pglogical password=pglogical',
  replication_sets := ARRAY['default']
);

host    replication     pglogical         10.50.4.10/32           trust


SELECT pglogical.create_node(
  node_name := 'bnr_subscriber',
  dsn := 'host=10.50.4.12 port=5433 dbname=dsacco_bnr user=pglogical password=pglogical'
);




SELECT pglogical.create_subscription(
  subscription_name := 'cdc_subscription',
  provider_dsn := 'host=10.50.4.12 port=5432 dbname=dsaccokigali_db user=pglogical password=pglogical',
  replication_sets := ARRAY['default','insert_only'],
  synchronize_structure := false,
  synchronize_data := false
);
