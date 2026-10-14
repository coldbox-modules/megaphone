/** Database checks against an explicitly provisioned, disposable local PostgreSQL database. */
component extends="commandbox-migrations.models.BaseMigrationCommand" {

    function run(
        numeric port = 60363,
        string database = "megaphone_api",
        string password = "megaphone-test",
        boolean roundtrip = true,
        string bundles = "tests.specs.integration.DatabaseInboxSpec,tests.specs.integration.EventStoreSpec,tests.specs.integration.DeliveryStoreSpec,tests.specs.integration.PreferenceStoreSpec,tests.specs.integration.SubscriptionStoreSpec,tests.specs.integration.EmailDigestSpec,tests.specs.integration.EmailDigestConcurrencySpec,tests.specs.unit.PreferenceResolverSpec,tests.specs.unit.SubscriptionCipherSpec,tests.specs.unit.EmailDigestScheduleSpec"
    ) {
        if ( !reFind( "^megaphone_api(_[a-f0-9]+)?$", arguments.database ) ) {
            throw( message = "Use an owned megaphone_api verification database." );
        }
        var datasource = installDatasource(
            {
                "type": "postgresql",
                "host": "127.0.0.1",
                "port": arguments.port,
                "username": "postgres",
                "password": arguments.password,
                "database": arguments.database
            },
            "megaphonePostgresAlignment",
            false
        );
        var root = fileSystemUtil.resolvePath( "." );
        fileSystemUtil.createMapping( "/megaphone", root );
        fileSystemUtil.createMapping( "/tests", root & "/tests" );
        fileSystemUtil.createMapping( "/testbox", root & "/testbox" );
        fileSystemUtil.createMapping( "/coldbox", root & "/tests/resources/app/coldbox" );
        var service = getInstance(
            name = "MigrationService@cfmigrations",
            initArguments = {
                "manager": "cfmigrations.models.QBMigrationManager",
                "migrationsDirectory": "/megaphone/resources/database/migrations/",
                "properties": {
                    "datasource": datasource,
                    "defaultGrammar": "PostgresGrammar@qb",
                    "schema": "public",
                    "migrationsTable": "megaphone_migrations"
                }
            }
        );
        service.install();
        service.runAllMigrations( "up" );
        if ( arguments.roundtrip ) {
            service.runAllMigrations( "down" );
            service.runAllMigrations( "up" );
        }
        fileSystemUtil.createMapping( "/qb", root & "/modules/qb" );
        fileSystemUtil.createMapping( "/cbpaginator", root & "/modules/qb/modules/cbpaginator" );
        fileSystemUtil.createMapping( "/str", root & "/modules/str" );
        var result = new testbox.system.TestBox( bundles = arguments.bundles ).run( reporter = "json" );
        fileWrite( root & "/.tmp/postgres-tests.json", result );
        var report = deserializeJSON( result );
        print.line( "PostgreSQL: " & report.totalPass & " passed, " & report.totalFail & " failed, " & report.totalError & " errors." );
        if ( report.totalFail || report.totalError ) {
            throw( message = "Inspect .tmp/postgres-tests.json." );
        }
    }

}
