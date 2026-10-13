component extends="testbox.system.BaseSpec" {

    /** Verifies the CI server uses its selected BoxLang mode and supported Java runtime. */
    public void function run() {
        if ( !structKeyExists( server, "boxlang" ) ) {
            return;
        }
        describe( "BoxLang CI runtime", () => {
            it( "runs the selected native or CFML compatibility mode on Java 21+", () => {
                var expectedMode = getSystemSetting( "MEGAPHONE_BOXLANG_MODE", "" );
                expect( listFind( "native,cfml", expectedMode ) ).toBeGT( 0 );
                var compatEnabled = structKeyExists( server.boxlang.modules, "compat-cfml" );
                expect( compatEnabled ).toBe( expectedMode == "cfml" );
                var javaVersion = createObject( "java", "java.lang.System" ).getProperty( "java.specification.version" );
                expect( val( javaVersion ) ).toBeGTE( 21 );
            } );
        } );
    }

}
