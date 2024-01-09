component extends="coldbox.system.testing.BaseTestCase" appMapping="/app" {

    property name="wirebox" inject="wirebox";

    function beforeAll() {
        super.beforeAll();

        getController().getModuleService().registerAndActivateModule( "megaphone", "testingModuleRoot" );

        getWireBox().autowire( this );

        variables.coldboxVersion = getController().getColdBoxSetting( "version" );
        variables.isColdBox6 = listFirst( variables.coldboxVersion, "." ) == "6";
    }

    /**
     * @beforeEach
     */
    function setupIntegrationTest() {
        setup();
    }

    /**
     * @aroundEach
     */
    function useDatabaseTransactions( spec ) {
        transaction action="begin" {
            try {
                arguments.spec.body();
            } catch ( any e ) {
                rethrow;
            } finally {
                transaction action="rollback";
            }
        }
    }

    function shutdownColdBox() {
        getColdBoxVirtualApp().shutdown();
    }

}
