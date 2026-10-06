/** AES-256-GCM authenticated storage with a rotation keyring and recipient/origin context. */
component {

    function init( required string activeKeyId, required struct keys ) {
        variables.activeKeyId = arguments.activeKeyId;
        variables.keys = {};
        for ( var id in arguments.keys ) {
            if ( !len( trim( id ) ) || !isSimpleValue( arguments.keys[ id ] ) ) {
                throw(
                    type = "Megaphone.Push.InvalidStorageKey",
                    message = "Storage keys require a key ID and base64 AES-256 key."
                );
            }
            try {
                var bytes = binaryDecode( arguments.keys[ id ], "base64" );
                if ( byteLength( bytes ) != 32 ) {
                    throw( message = "Invalid length." );
                }
                variables.keys[ id ] = createObject( "java", "javax.crypto.spec.SecretKeySpec" ).init( bytes, "AES" );
            } catch ( any error ) {
                throw(
                    type = "Megaphone.Push.InvalidStorageKey",
                    message = "Each storage key must decode to 32 bytes."
                );
            }
        }
        if ( !structKeyExists( variables.keys, variables.activeKeyId ) ) {
            throw( type = "Megaphone.Push.MissingStorageKey", message = "The active storage key ID is not configured." );
        }
        return this;
    }

    public string function seal( required struct subscription, required string context ) {
        validateContext( arguments.context );
        var iv = binaryDecode( repeatString( "00", 12 ), "hex" );
        createObject( "java", "java.security.SecureRandom" ).init().nextBytes( iv );
        var cipher = createObject( "java", "javax.crypto.Cipher" ).getInstance( "AES/GCM/NoPadding" );
        cipher.init(
            javacast( "int", 1 ),
            variables.keys[ variables.activeKeyId ],
            createObject( "java", "javax.crypto.spec.GCMParameterSpec" ).init( javacast( "int", 128 ), iv )
        );
        cipher.updateAAD( aad( variables.activeKeyId, arguments.context ) );
        var encrypted = cipher.doFinal( charsetDecode( serializeJSON( arguments.subscription ), "UTF-8" ) );
        return serializeJSON( {
            "version": 1,
            "keyId": variables.activeKeyId,
            "iv": binaryEncode( iv, "base64" ),
            "ciphertext": binaryEncode( encrypted, "base64" )
        } );
    }

    public struct function unseal( required string sealedData, required string context ) {
        validateContext( arguments.context );
        try {
            var envelope = deserializeJSON( arguments.sealedData );
            if ( !isStruct( envelope ) || envelope.version != 1 || !structKeyExists( variables.keys, envelope.keyId ) ) {
                throw( message = "Unsupported envelope or missing key." );
            }
            var iv = binaryDecode( envelope.iv, "base64" );
            var encrypted = binaryDecode( envelope.ciphertext, "base64" );
            if ( byteLength( iv ) != 12 || byteLength( encrypted ) < 16 ) {
                throw( message = "Invalid envelope." );
            }
            var cipher = createObject( "java", "javax.crypto.Cipher" ).getInstance( "AES/GCM/NoPadding" );
            cipher.init(
                javacast( "int", 2 ),
                variables.keys[ envelope.keyId ],
                createObject( "java", "javax.crypto.spec.GCMParameterSpec" ).init( javacast( "int", 128 ), iv )
            );
            cipher.updateAAD( aad( envelope.keyId, arguments.context ) );
            var subscription = deserializeJSON( charsetEncode( cipher.doFinal( encrypted ), "UTF-8" ) );
            if ( !isStruct( subscription ) ) {
                throw( message = "Invalid subscription." );
            }
            return subscription;
        } catch ( any error ) {
            // Never include endpoints, keys, plaintext, or ciphertext in exception details.
            throw(
                type = "Megaphone.Push.InvalidSealedData",
                message = "Unable to open the subscription for this configured key and context."
            );
        }
    }

    private any function aad( required string keyId, required string context ) {
        return charsetDecode( "megaphone-webpush:v1:" & arguments.keyId & ":" & arguments.context, "UTF-8" );
    }
    private numeric function byteLength( required any value ) {
        return createObject( "java", "java.lang.reflect.Array" ).getLength( arguments.value );
    }
    private void function validateContext( required string context ) {
        if ( !len( trim( arguments.context ) ) ) {
            throw(
                type = "Megaphone.Push.InvalidStorageContext",
                message = "A recipient and origin storage context is required."
            );
        }
    }

}
