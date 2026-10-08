component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "Sealed subscription material", () => {
            beforeEach( () => {
                variables.key = binaryEncode( binaryDecode( repeatString( "01", 32 ), "hex" ), "base64" );
                variables.cipher = new megaphone.models.SubscriptionCipher(
                    activeKeyId = "one",
                    keys = { "one": variables.key }
                );
                variables.subscription = {
                    "endpoint": "https://push.example.test/private-destination",
                    "keys": { "auth": "test-auth", "p256dh": "test-public" }
                };
                variables.context = "User:one:https://app.example.test";
            } );
            it( "encrypts and authenticates a subscription without exposing its endpoint or keys", () => {
                var sealed = variables.cipher.seal( variables.subscription, variables.context );
                expect( sealed ).notToInclude( variables.subscription.endpoint );
                expect( sealed ).notToInclude( "test-auth" );
                var opened = variables.cipher.unseal( sealed, variables.context );
                expect( opened.endpoint ).toBe( variables.subscription.endpoint );
                expect( opened.keys.auth ).toBe( "test-auth" );
            } );
            it( "uses a new nonce for every encryption", () => {
                var first = variables.cipher.seal( variables.subscription, variables.context );
                var second = variables.cipher.seal( variables.subscription, variables.context );
                expect( deserializeJSON( first ).iv ).notToBe( deserializeJSON( second ).iv );
                expect( first ).notToBe( second );
            } );
            it( "rejects tampered ciphertext and a different recipient or origin", () => {
                var sealed = variables.cipher.seal( variables.subscription, variables.context );
                var envelope = deserializeJSON( sealed );
                envelope.ciphertext = ( left( envelope.ciphertext, 1 ) == "A" ? "B" : "A" ) & mid(
                    envelope.ciphertext,
                    2,
                    len( envelope.ciphertext ) - 1
                );
                expect( () => variables.cipher.unseal( serializeJSON( envelope ), variables.context ) ).toThrow(
                    type = "Megaphone.Push.InvalidSealedData"
                );
                expect( () => variables.cipher.unseal( sealed, "User:other:https://app.example.test" ) ).toThrow(
                    type = "Megaphone.Push.InvalidSealedData"
                );
                expect( () => variables.cipher.unseal( sealed, "User:one:https://other.example.test" ) ).toThrow(
                    type = "Megaphone.Push.InvalidSealedData"
                );
            } );
            it( "reads a retained old key while new subscriptions use the active rotation key", () => {
                var sealed = variables.cipher.seal( variables.subscription, variables.context );
                var nextKey = binaryEncode( binaryDecode( repeatString( "02", 32 ), "hex" ), "base64" );
                var rotated = new megaphone.models.SubscriptionCipher(
                    activeKeyId = "two",
                    keys = { "one": variables.key, "two": nextKey }
                );
                expect( rotated.unseal( sealed, variables.context ).keys.auth ).toBe( "test-auth" );
                expect( deserializeJSON( rotated.seal( variables.subscription, variables.context ) ).keyId ).toBe( "two" );
                var dropped = new megaphone.models.SubscriptionCipher( activeKeyId = "two", keys = { "two": nextKey } );
                expect( () => dropped.unseal( sealed, variables.context ) ).toThrow(
                    type = "Megaphone.Push.InvalidSealedData"
                );
            } );
            it( "rejects invalid configuration and empty ownership context", () => {
                expect( () => new megaphone.models.SubscriptionCipher( activeKeyId = "missing", keys = {} ) ).toThrow(
                    type = "Megaphone.Push.MissingStorageKey"
                );
                expect( () => new megaphone.models.SubscriptionCipher( activeKeyId = "one", keys = { "one": "short" } ) ).toThrow(
                    type = "Megaphone.Push.InvalidStorageKey"
                );
                expect( () => variables.cipher.seal( variables.subscription, "" ) ).toThrow(
                    type = "Megaphone.Push.InvalidStorageContext"
                );
            } );
        } );
    }

}
