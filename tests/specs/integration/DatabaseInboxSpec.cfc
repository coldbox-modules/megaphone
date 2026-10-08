/** Real persistence through public Megaphone APIs; migrations run outside specs. */
component extends="testbox.system.BaseSpec" {

    function beforeAll() {
        variables.injector = new coldbox.system.ioc.Injector( binder = "tests.resources.InboxTestBinder" );
        var binder = variables.injector.getBinder();
        variables.isPostgres = structKeyExists( application, "applicationName" ) && application.applicationName == "CommandBox CLI";
        variables.grammar = variables.isPostgres ? new qb.models.Grammars.PostgresGrammar() : new qb.models.Grammars.MySQLGrammar();
        variables.databaseProperties = {
            "inboxState": true,
            "idSqlType": variables.isPostgres ? "other" : "varchar",
            "cursorTimestampExpression": variables.isPostgres ? "CAST(""createdDate"" AS TEXT)" : "CAST(`createdDate` AS CHAR)",
            "cursorTimestampSqlType": variables.isPostgres ? "other" : "timestamp"
        };
        if ( structKeyExists( application, "applicationName" ) && application.applicationName == "CommandBox CLI" ) {
            variables.grammar.setInterceptorService( application.wirebox.getInstance( "box:interceptorService" ) );
        }
        binder.map( "str@str" ).toValue( createObject( "component", "str.models.Str" ) );
        binder
            .map( "QueryBuilder@qb" )
            .to( "qb.models.Query.QueryBuilder" )
            .initArg( name = "grammar", value = variables.grammar );
        binder
            .map( "DatabaseProvider@megaphone" )
            .to( "megaphone.models.Providers.DatabaseProvider" )
            .initArg( name = "name", value = "database" )
            .initArg( name = "properties", value = variables.databaseProperties );
        binder.map( "DatabaseNotificationCursor@megaphone" ).to( "megaphone.models.DatabaseNotificationCursor" );
        binder.map( "DatabaseNotification@megaphone" ).to( "megaphone.models.DatabaseNotification" );
        binder
            .map( "DatabaseNotificationService@megaphone" )
            .to( "megaphone.models.Delegates.DatabaseNotificationService" );
        binder.map( "NotificationService@megaphone" ).to( "megaphone.models.NotificationService" );
        variables.injector.registerDSL( "megaphone", "megaphone.dsl.MegaphoneDSL" );
        variables.injector
            .getInstance( "NotificationService@megaphone" )
            .registerChannels( { "database": { "provider": "DatabaseProvider@megaphone", "properties": variables.databaseProperties } } );
        variables.inbox = variables.injector.getInstance( "DatabaseNotificationService@megaphone" );
    }

    function afterAll() {
        if ( structKeyExists( variables, "injector" ) ) {
            variables.injector.shutdown();
        }
    }

    function run() {
        describe( "Recipient-owned database inbox", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient().setId( createUUID() );
                variables.other = new tests.resources.InboxRecipient().setId( createUUID() );
            } );
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );

            it( "applies visibility before pagination and counts, including OR constraints", () => {
                var visible = store( variables.owner, "visible", "one" );
                store( variables.owner, "hidden", "two" );
                store( variables.other, "foreign", "one" );
                var permitted = function( qb ) {
                    return qb.where( "groupKey", "one" ).orWhere( "type", "foreign" );
                };
                var page = variables.inbox.getNotifications(
                    notifiable = variables.owner,
                    maxRows = 1,
                    constraints = permitted,
                    archiveMode = "active"
                );
                expect( page.getPagination().totalRecords ).toBe( 1 );
                expect( page.getResults()[ 1 ].getId() ).toBe( visible.getId() );
                expect(
                    variables.inbox.countUnreadNotifications(
                        notifiable = variables.owner,
                        constraints = permitted,
                        archiveMode = "active"
                    )
                ).toBe( 1 );
                expect( isNull( variables.inbox.getNotification( variables.other, visible.getId() ) ) ).toBeTrue();
            } );

            it( "continues past deleted boundaries without repeats after concurrent arrivals", () => {
                var oldest = store(
                    variables.owner,
                    "old",
                    "one",
                    dateAdd( "s", -3, now() )
                );
                var middle = store(
                    variables.owner,
                    "middle",
                    "one",
                    dateAdd( "s", -2, now() )
                );
                var newest = store(
                    variables.owner,
                    "new",
                    "one",
                    dateAdd( "s", -1, now() )
                );
                store( variables.other, "foreign", "one" );
                var first = variables.inbox.getNotificationSlice( notifiable = variables.owner, maxRows = 1 );
                expect( first.results[ 1 ].getId() ).toBe( newest.getId() );
                newest.delete();
                store( variables.owner, "arrival", "one" );
                var second = variables.inbox.getNotificationSlice(
                    notifiable = variables.owner,
                    maxRows = 1,
                    afterCursor = first.nextCursor
                );
                expect( second.results[ 1 ].getId() ).toBe( middle.getId() );
                var third = variables.inbox.getNotificationSlice(
                    notifiable = variables.owner,
                    maxRows = 1,
                    afterCursor = second.nextCursor
                );
                expect( third.results[ 1 ].getId() ).toBe( oldest.getId() );
                expect( third.hasMore ).toBeFalse();
                expect( third.nextCursor ).toBe( "" );
                expect( function() {
                    return variables.inbox.getNotificationSlice(
                        notifiable = variables.other,
                        afterCursor = first.nextCursor
                    );
                } ).toThrow( "Megaphone.Database.InvalidCursor" );
            } );

            it( "preserves stored timestamp boundaries and orders equal dates by ID", () => {
                var records = [
                    store( variables.owner, "one" ),
                    store( variables.owner, "two" ),
                    store( variables.owner, "three" )
                ];
                for ( var index = 1; index <= records.len(); index++ ) {
                    queryExecute(
                        variables.isPostgres ? "UPDATE megaphone_notifications SET ""createdDate""=CAST(:stamp AS timestamp) WHERE id=:id" : "UPDATE megaphone_notifications SET `createdDate`=:stamp WHERE id=:id",
                        {
                            "stamp": "2026-01-01 12:00:" & ( variables.isPostgres ? "00.000" : "0" ) & index,
                            "id": {
                                "value": records[ index ].getId(),
                                "cfsqltype": variables.databaseProperties.idSqlType
                            }
                        }
                    );
                }
                var first = variables.inbox.getNotificationSlice( notifiable = variables.owner, maxRows = 1 );
                expect( first.results[ 1 ].getId() ).toBe( records[ 3 ].getId() );
                var second = variables.inbox.getNotificationSlice(
                    notifiable = variables.owner,
                    maxRows = 1,
                    afterCursor = first.nextCursor
                );
                expect( second.results[ 1 ].getId() ).toBe( records[ 2 ].getId() );
                var third = variables.inbox.getNotificationSlice(
                    notifiable = variables.owner,
                    maxRows = 1,
                    afterCursor = second.nextCursor
                );
                expect( third.results[ 1 ].getId() ).toBe( records[ 1 ].getId() );
                var tiedDate = now();
                for ( var record in records ) {
                    queryExecute(
                        variables.isPostgres ? "UPDATE megaphone_notifications SET ""createdDate""=:stamp WHERE id=:id" : "UPDATE megaphone_notifications SET `createdDate`=:stamp WHERE id=:id",
                        {
                            "stamp": { "value": tiedDate, "cfsqltype": "timestamp" },
                            "id": { "value": record.getId(), "cfsqltype": variables.databaseProperties.idSqlType }
                        }
                    );
                }
                var expected = variables.inbox
                    .getNotifications( variables.owner )
                    .getResults()
                    .map( function( record ) {
                        return record.getId();
                    } );
                first = variables.inbox.getNotificationSlice( notifiable = variables.owner, maxRows = 1 );
                second = variables.inbox.getNotificationSlice(
                    notifiable = variables.owner,
                    maxRows = 1,
                    afterCursor = first.nextCursor
                );
                expect( first.results[ 1 ].getId() ).toBe( expected[ 1 ] );
                expect( second.results[ 1 ].getId() ).toBe( expected[ 2 ] );
            } );

            it( "preserves dates and read state in idempotent imports", () => {
                var id = createUUID();
                var created = dateAdd( "d", -30, now() );
                var read = dateAdd( "d", -20, now() );
                variables.inbox.importNotification(
                    notifiable = variables.owner,
                    id = id,
                    type = "history",
                    data = { "message": "Original" },
                    createdDate = created,
                    readDate = read,
                    groupKey = "one"
                );
                var imported = variables.inbox.importNotification(
                    notifiable = variables.owner,
                    id = id,
                    type = "history",
                    data = { "message": "Original" }
                );
                expect( dateDiff( "s", created, imported.getCreatedDate() ) ).toBe( 0 );
                expect( dateDiff( "s", read, imported.getReadDate() ) ).toBe( 0 );
                expect( variables.inbox.getNotifications( variables.owner ).getPagination().totalRecords ).toBe( 1 );
                expect( function() {
                    return variables.inbox.importNotification(
                        notifiable = variables.other,
                        id = id,
                        type = "history",
                        data = {}
                    );
                } ).toThrow( type = "Megaphone.Database.ImportConflict" );
            } );

            it( "keeps filtered notification handles current through read and archive transitions", () => {
                var imported = store( variables.owner, "notice", "one" );
                var notice = variables.inbox.getNotificationSlice(
                    notifiable = variables.owner,
                    archiveMode = "active",
                    unread = true
                ).results[ 1 ];
                notice.markAsRead();
                expect( isDate( notice.getReadDate() ) ).toBeTrue();
                notice.archive();
                expect( isDate( notice.getArchivedDate() ) ).toBeTrue();
                notice.unarchive();
                expect( isDate( notice.getArchivedDate() ) ).toBeFalse();
                notice.delete();
                expect( isNull( variables.inbox.getNotification( variables.owner, imported.getId() ) ) ).toBeTrue();
            } );
            it( "archives without marking read and restores unread counts", () => {
                var notice = store( variables.owner, "notice", "one" );
                notice.archive();
                expect(
                    variables.inbox.countUnreadNotifications( notifiable = variables.owner, archiveMode = "active" )
                ).toBe( 0 );
                var archived = variables.inbox
                    .getNotifications( notifiable = variables.owner, archiveMode = "archived" )
                    .getResults()[ 1 ];
                expect( isDate( archived.getReadDate() ) ).toBeFalse();
                archived.unarchive();
                expect(
                    variables.inbox.countUnreadNotifications( notifiable = variables.owner, archiveMode = "active" )
                ).toBe( 1 );
            } );

            it( "preserves the first read and archive timestamps on repeated mutations", () => {
                var notice = store( variables.owner, "notice", "one" );
                var first = dateAdd( "h", -1, now() );
                notice.markAsRead( first );
                notice.markAsRead( now() );
                expect( dateDiff( "s", first, notice.getReadDate() ) ).toBe( 0 );
                notice.archive( first );
                notice.archive( now() );
                expect( dateDiff( "s", first, notice.getArchivedDate() ) ).toBe( 0 );
                notice.unarchive();
                expect( isDate( notice.getArchivedDate() ) ).toBeFalse();
                expect( dateDiff( "s", first, notice.getReadDate() ) ).toBe( 0 );
            } );

            it( "marks a recipient-owned snapshot without consuming later arrivals or foreign IDs", () => {
                var earlier = store( variables.owner, "earlier", "one" );
                var foreign = store( variables.other, "foreign", "one" );
                var ids = variables.inbox.snapshotIds( variables.owner );
                var later = store( variables.owner, "later", "one" );
                ids.append( foreign.getId() );
                variables.inbox.markSnapshotAsRead( variables.owner, ids );
                expect( isDate( variables.inbox.getNotification( variables.owner, earlier.getId() ).getReadDate() ) ).toBeTrue();
                expect( isDate( variables.inbox.getNotification( variables.owner, later.getId() ).getReadDate() ) ).toBeFalse();
                expect( isDate( variables.inbox.getNotification( variables.other, foreign.getId() ).getReadDate() ) ).toBeFalse();
            } );

            it( "retains live authorization constraints during individual mutation", () => {
                var notice = store( variables.owner, "notice", "one" );
                // The SQL constraint reads live database state rather than a previously fetched page.
                var constrained = variables.inbox.getNotification(
                    notifiable = variables.owner,
                    id = notice.getId(),
                    constraints = function( qb ) {
                        return qb.where( "groupKey", "one" );
                    }
                );
                // A real scope change invalidates the original object's mutation query.
                new qb.models.Query.QueryBuilder( grammar = variables.grammar )
                    .from( "megaphone_notifications" )
                    .where( "id", { "value": notice.getId(), "cfsqltype": variables.databaseProperties.idSqlType } )
                    .update( { "groupKey": "two" } );
                constrained.markAsRead();
                expect( isDate( variables.inbox.getNotification( variables.owner, notice.getId() ).getReadDate() ) ).toBeFalse();
                expect( variables.inbox.countUnreadNotifications( variables.owner ) ).toBe( 1 );
            } );

            it( "prunes oldest inbox entries in bounded batches including archives without touching another user", () => {
                var oldest = store(
                    variables.owner,
                    "oldest",
                    "one",
                    dateAdd( "d", -3, now() )
                );
                oldest.archive();
                store(
                    variables.owner,
                    "middle",
                    "one",
                    dateAdd( "d", -2, now() )
                );
                var latest = store(
                    variables.owner,
                    "latest",
                    "one",
                    dateAdd( "d", -1, now() )
                );
                var foreign = store( variables.other, "foreign", "one" );
                expect( variables.inbox.pruneNotifications( notifiable = variables.owner, keep = 1, batchSize = 1 ) ).toBe(
                    1
                );
                expect( variables.inbox.pruneNotifications( notifiable = variables.owner, keep = 1, batchSize = 1 ) ).toBe(
                    1
                );
                expect( variables.inbox.pruneNotifications( notifiable = variables.owner, keep = 1 ) ).toBe( 0 );
                expect( variables.inbox.getNotifications( variables.owner ).getResults()[ 1 ].getId() ).toBe(
                    latest.getId()
                );
                expect( isNull( variables.inbox.getNotification( variables.other, foreign.getId() ) ) ).toBeFalse();
            } );
        } );
    }

    private any function store(
        required any owner,
        required string type,
        string groupKey = "",
        date createdDate = now()
    ) {
        return variables.inbox.importNotification(
            notifiable = arguments.owner,
            id = createUUID(),
            type = arguments.type,
            data = { "message": arguments.type },
            groupKey = arguments.groupKey,
            createdDate = arguments.createdDate
        );
    }

}
