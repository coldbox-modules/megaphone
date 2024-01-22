component extends="tests.resources.ModuleIntegrationSpec" {

    property name="mailService" inject="MailService@cbmailservices";
    property name="megaphone" inject="NotificationService@megaphone";
    property name="binder" inject="wirebox:binder";

    function run() {
        describe( "email notification provider", () => {
            beforeEach( () => {
                variables.mailService.getMailer( "default" ).transit.reset();
            } );

            it( "throws an exception if cbmailservices is not installed", () => {
                var mailServiceMapping = variables.binder.getMapping( "MailService@cbmailservices" );
                try {
                    variables.binder.unmap( "MailService@cbmailservices" );
                    expect( () => {
                        variables.wirebox.getInstance( "EmailProvider@megaphone", { "name": "mail", "properties": {} } );
                    } ).toThrow( type = "Megaphone.Provider.MissingDependency" );
                } finally {
                    variables.binder.setMapping( "MailService@cbmailservices", mailServiceMapping );
                }
            } );

            it( "throws an exception if no email address is set and no routeNotificationForEmail method is defined", () => {
                var testNotifiable = { "getNotifiableId": () => 1, "getNotifiableType": () => "test" };

                expect( () => {
                    variables.megaphone.notify( testNotifiable, "TestImplicitEmailNotification", {} );
                } ).toThrow( type = "Megaphone.Notification.MissingRoutingForMethod" );

                var mailer = variables.mailService.getMailer( "default" );
                var sentMail = mailer.transit.getMail();
                expect( sentMail ).toBeArray();
                expect( sentMail ).toBeEmpty();
            } );

            it( "uses the provided email address if set", () => {
                var testNotifiable = {
                    "getNotifiableId": () => 1,
                    "getNotifiableType": () => "test",
                    "getEmail": () => "test@example.com"
                };

                var notification = variables.megaphone.notify( testNotifiable, "TestExplicitToEmailNotification", {} );

                var mailer = variables.mailService.getMailer( "default" );
                var sentMail = mailer.transit.getMail();
                expect( sentMail ).toBeArray();
                expect( sentMail ).toHaveLength( 1 );
                expect( sentMail[ 1 ].to ).toBe( testNotifiable.getEmail() );
                expect( sentMail[ 1 ].subject ).toBe( "Megaphone Email Notification" );
            } );

            it( "calls routeNotificationForEmail if no to address is set", () => {
                var testEmail = "test@example.com";
                var testNotifiable = {
                    "getNotifiableId": () => 1,
                    "getNotifiableType": () => "test",
                    "routeNotificationForEmail": () => testEmail
                };

                var notification = variables.megaphone.notify( testNotifiable, "TestImplicitEmailNotification", {} );

                var mailer = variables.mailService.getMailer( "default" );
                var sentMail = mailer.transit.getMail();
                expect( sentMail ).toBeArray();
                expect( sentMail ).toHaveLength( 1 );
                expect( sentMail[ 1 ].to ).toBe( testEmail );
                expect( sentMail[ 1 ].subject ).toBe( "Megaphone Email Notification" );
            } );
        } );
    }

}
