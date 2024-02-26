component extends="tests.resources.ModuleIntegrationSpec" {

    property name="megaphone" inject="NotificationService@megaphone";

    function run() {
        describe( "custom notification provider", () => {
            beforeEach( () => structDelete( application, "customNotificationSent" ) );

            it( "routes to a WireBox mapping if no channel is defined", () => {
                expect( application ).notToHaveKey( "customNotificationSent" );
                variables.megaphone.notify(
                    { "getNotifiableId": () => 1, "getNotifiableType": () => "test" },
                    wirebox.getInstance( "CustomNotification" )
                );
                expect( application ).toHaveKey( "customNotificationSent" );
                expect( application.customNotificationSent ).toBeTrue();
            } );
        } );
    }

}
