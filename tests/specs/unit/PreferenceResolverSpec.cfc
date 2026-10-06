component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "Ordered channel preferences", () => {
            beforeEach( () => {
                variables.resolver = new megaphone.models.PreferenceResolver();
                variables.defaults = { "database": true, "email": false, "push": false };
            } );

            it( "keeps independent channel defaults when no choices exist", () => {
                var result = variables.resolver.resolve( variables.defaults );
                expect( result.database ).toBe( { "enabled": true, "source": "default" } );
                expect( result.email.enabled ).toBeFalse();
                expect( result.push.enabled ).toBeFalse();
            } );

            it( "resolves each channel through account, organization, and production choices", () => {
                var result = variables.resolver.resolve(
                    variables.defaults,
                    [
                        { "key": "account", "choices": { "database": "off", "email": "on" } },
                        { "key": "organization:one", "choices": { "database": "on", "email": "inherit", "push": "on" } },
                        { "key": "production:two", "choices": { "email": "off", "push": "inherit" } }
                    ]
                );
                expect( result.database ).toBe( { "enabled": true, "source": "organization:one" } );
                expect( result.email ).toBe( { "enabled": false, "source": "production:two" } );
                expect( result.push ).toBe( { "enabled": true, "source": "organization:one" } );
                expect( variables.defaults.email ).toBeFalse();
            } );

            it( "does not interpret false-like strings as an opt in", () => {
                expect( () => variables.resolver.resolve(
                    variables.defaults,
                    [ { "key": "account", "choices": { "push": "false" } } ]
                ) ).toThrow( type = "Megaphone.Preferences.InvalidChoice" );
                expect( () => variables.resolver.resolve(
                    variables.defaults,
                    [ { "key": "account", "choices": { "sms": "on" } } ]
                ) ).toThrow( type = "Megaphone.Preferences.UnknownChannel" );
            } );

            it( "includes future devices while retaining exclusions and retiring inactive devices", () => {
                var devices = [
                    { "id": "phone", "active": true },
                    { "id": "laptop", "active": true },
                    { "id": "old", "active": false }
                ];
                expect( variables.resolver.selectDevices( devices, [ "phone" ] ).map( ( device ) => device.id ) ).toBe( [ "laptop" ] );
                devices.append( { "id": "tablet", "active": true } );
                devices.append( { "id": "laptop", "active": true } );
                expect( variables.resolver.selectDevices( devices, [ "phone" ] ).map( ( device ) => device.id ) ).toBe( [ "laptop", "tablet" ] );
            } );
        } );
    }

}
