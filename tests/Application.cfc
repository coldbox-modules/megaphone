component {

    this.name = "ColdBoxTestingSuite" & hash(getCurrentTemplatePath());
    this.sessionManagement  = true;
    this.setClientCookies   = true;
    this.sessionTimeout     = createTimeSpan( 0, 0, 15, 0 );
    this.applicationTimeout = createTimeSpan( 0, 0, 15, 0 );
    this.timezone = "UTC";

    // Turn on/off white space management
	this.whiteSpaceManagement = "smart";

    testsPath = getDirectoryFromPath( getCurrentTemplatePath() );
    this.mappings[ "/tests" ] = testsPath;
    rootPath = REReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
    this.mappings[ "/root" ] = rootPath;
    this.javaSettings = { "loadPaths": [ rootPath & "resources/java/webpush" ], "loadColdFusionClassPath": true };
    this.mappings[ "/testingModuleRoot" ] = listDeleteAt( rootPath, listLen( rootPath, '\/' ), "\/" );
    this.mappings[ "/megaphone" ] = rootPath;
    this.mappings[ "/qb" ] = rootPath & "/modules/qb";
    this.mappings[ "/cbpaginator" ] = rootPath & "/modules/qb/modules/cbpaginator";
    this.mappings[ "/cfmigrations" ] = rootPath & "/modules/cfmigrations";
    this.mappings[ "/str" ] = rootPath & "/modules/str";
    this.mappings[ "/app" ] = testsPath & "resources/app";
    this.mappings[ "/coldbox" ] = testsPath & "resources/app/coldbox";
    this.mappings[ "/testbox" ] = rootPath & "/testbox";
    this.mappings[ "/hyper" ] = rootPath & "/modules/hyper";
    this.mappings[ "/hyper" ] = testsPath & "resources/app/modules/hyper";
    this.mappings[ "/globber" ] = testsPath & "resources/app/modules/hyper/modules/globber";

    this.datasource = "megaphone";

    function onRequestStart() {
        // applicationStop();
        // abort;
        setting requestTimeout="180";

        // New ColdBox Virtual Application Starter
		request.coldBoxVirtualApp = new coldbox.system.testing.VirtualApp( appMapping = "/app" );

        if ( structKeyExists( url, "fwreinit" ) || structKeyExists( url, "reloadDatabase" ) ) {
            if ( structKeyExists( server, "lucee" ) ) {
                pagePoolClear();
            }
        }

        // Start once per runner request; onRequestEnd shuts down the virtual app.
        if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
            request.coldBoxVirtualApp.startup();
        }

        return true;
    }

    public void function onRequestEnd( required targetPage ) {
		request.coldBoxVirtualApp.shutdown();
	}


}
