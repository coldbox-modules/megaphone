component extends="tests.specs.integration.DatabaseInboxSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector
            .getBinder()
            .map( "PreferenceResolver@megaphone" )
            .to( "megaphone.models.PreferenceResolver" );
        variables.injector
            .getBinder()
            .map( "PreferenceStore@megaphone" )
            .to( "megaphone.models.PreferenceStore" );
        variables.preferences = variables.injector.getInstance( "PreferenceStore@megaphone" );
    }
    function run() {
        describe( "Stored channel preferences", () => {
            aroundEach( ( spec ) => {
                transaction {
                    try {
                        variables.owner = new tests.resources.InboxRecipient();
                        variables.other = new tests.resources.InboxRecipient();
                        variables.defaults = { "database": true, "email": false, "push": false };
                        spec.body();
                    } finally {
                        transactionRollback();
                    }
                }
            } );
            it( "prunes constrained stale choices in bounded batches without touching other scopes", () => {
                save( "organization:deleted", "database", "off" );
                save( "organization:deleted", "email", "on" );
                save( "organization:live", "email", "off" );
                save( "account", "email", "on" );
                var stale = ( query ) => query.where( "scopeKey", "organization:deleted" );
                expect( variables.preferences.pruneChoices( stale, 1 ) ).toBe( 1 );
                expect( variables.preferences.pruneChoices( stale, 1 ) ).toBe( 1 );
                expect( variables.preferences.pruneChoices( stale, 1 ) ).toBe( 0 );
                var choices = variables.preferences.choices(
                    variables.owner,
                    "submitted",
                    [ "account", "organization:live" ]
                );
                expect( choices[ 1 ].choices.email ).toBe( "on" );
                expect( choices[ 2 ].choices.email ).toBe( "off" );
                expect( () => variables.preferences.pruneChoices( stale, 0 ) ).toThrow( "Megaphone.Preferences.InvalidBatch" );
            } );
            it( "resolves ordered scopes and exposes effective sources independently per channel", () => {
                save( "account", "email", "on" );
                save( "organization:one", "database", "off" );
                save( "production:one", "email", "off" );
                var result = configuration();
                expect( result.effective.email.enabled ).toBeFalse();
                expect( result.effective.email.source ).toBe( "production:one" );
                expect( result.effective.database.enabled ).toBeFalse();
                expect( result.effective.database.source ).toBe( "organization:one" );
                expect( result.effective.push.enabled ).toBeFalse();
                expect( result.effective.push.source ).toBe( "default" );
                expect( result.scopes[ 1 ].key ).toBe( "account" );
            } );
            it( "imports missing choices without replacing explicit settings or materializing inherit", () => {
                variables.preferences.importChoice(
                    variables.owner,
                    "submitted",
                    "account",
                    "email",
                    "on"
                );
                variables.preferences.importChoice(
                    variables.owner,
                    "submitted",
                    "account",
                    "email",
                    "off"
                );
                variables.preferences.importChoice(
                    variables.owner,
                    "submitted",
                    "production:one",
                    "email",
                    "inherit"
                );
                expect( configuration().effective.email.enabled ).toBeTrue();
                expect( configuration().scopes[ 3 ].choices.isEmpty() ).toBeTrue();
                expect(
                    variables.preferences.choices( variables.other, "submitted", [ "account" ] )[ 1 ].choices.isEmpty()
                ).toBeTrue();
            } );
            it( "updates atomically and removes an explicit override on inherit", () => {
                save( "account", "email", "on" );
                save( "production:one", "email", "off" );
                save( "production:one", "email", "on" );
                expect( configuration().effective.email.source ).toBe( "production:one" );
                save( "production:one", "email", "inherit" );
                var result = configuration();
                expect( result.scopes[ 3 ].choices.isEmpty() ).toBeTrue();
                expect( result.effective.email.enabled ).toBeTrue();
                expect( result.effective.email.source ).toBe( "account" );
            } );
            it( "isolates recipients types notification types and scopes", () => {
                save( "account", "email", "on" );
                variables.preferences.saveChoice(
                    variables.other,
                    "submitted",
                    "account",
                    "push",
                    "on"
                );
                variables.preferences.saveChoice(
                    variables.owner,
                    "offer",
                    "account",
                    "push",
                    "on"
                );
                save( "production:two", "push", "on" );
                var result = configuration();
                expect( result.effective.email.enabled ).toBeTrue();
                expect( result.effective.push.enabled ).toBeFalse();
                var sameIdDifferentType = new tests.resources.InboxRecipient(
                    id = variables.owner.getId(),
                    type = "Team"
                );
                expect(
                    variables.preferences.configuration(
                        sameIdDifferentType,
                        "submitted",
                        variables.defaults,
                        [ "account" ]
                    ).effective.email.enabled
                ).toBeFalse();
            } );
            it( "rejects invalid choices before persistence", () => {
                expect( () => save( "account", "email", "yes" ) ).toThrow(
                    type = "Megaphone.Preferences.InvalidChoice"
                );
                expect( () => save( "", "email", "on" ) ).toThrow( type = "Megaphone.Preferences.InvalidKey" );
                expect( configuration().effective.email.enabled ).toBeFalse();
            } );
            it( "cleans up only the deleted recipient's choices", () => {
                save( "account", "email", "on" );
                variables.preferences.saveChoice(
                    variables.other,
                    "submitted",
                    "account",
                    "email",
                    "on"
                );
                variables.preferences.deleteRecipient( variables.owner );
                expect( configuration().effective.email.enabled ).toBeFalse();
                expect(
                    variables.preferences.configuration(
                        variables.other,
                        "submitted",
                        variables.defaults,
                        [ "account" ]
                    ).effective.email.enabled
                ).toBeTrue();
            } );
        } );
    }
    private void function save( required string scope, required string channel, required string choice ) {
        variables.preferences.saveChoice(
            variables.owner,
            "submitted",
            arguments.scope,
            arguments.channel,
            arguments.choice
        );
    }
    private struct function configuration() {
        return variables.preferences.configuration(
            variables.owner,
            "submitted",
            variables.defaults,
            [ "account", "organization:one", "production:one" ]
        );
    }

}
