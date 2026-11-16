/** Boots the Lucee snapshot with CFConfig's JSON provider until it supports Lucee 8. */
component {

    function run() {
        var configService = getInstance( "CFConfigService@cfconfig-services" );
        var providers = configService.getProviderRegistry();
        // Lucee 8 retains the Lucee 7 JSON configuration format. Keep this adapter in CI only.
        for ( var provider in duplicate( providers ) ) {
            if ( reFind( "Lucee7(Server|Web)$", provider.invocationPath ) ) {
                var snapshotProvider = duplicate( provider );
                snapshotProvider.version = "8";
                providers.prepend( snapshotProvider );
            }
        }
        command( "server start" ).params( cfengine = "lucee@be", javaVersion = "openjdk21_jdk" ).run();
    }

}
