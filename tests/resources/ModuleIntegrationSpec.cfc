component extends="coldbox.system.testing.BaseTestCase" appMapping="/app" {

	/*********************************** LIFE CYCLE Methods ***********************************/

	function beforeAll() {
		super.beforeAll();

		getController().getModuleService().registerAndActivateModule( "megaphone", "testingModuleRoot" );

		getWireBox().autowire( this );
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
