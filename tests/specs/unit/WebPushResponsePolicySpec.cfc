component extends="testbox.system.BaseSpec" {

    function run() {
        describe( "Web push response outcomes", () => {
            beforeEach( () => {
                variables.policy = new megaphone.models.WebPushResponsePolicy();
                variables.clock = parseDateTime( "2026-10-05T12:00:00Z" );
            } );
            it( "records provider acceptance without claiming user delivery", () => {
                for ( var code in [ 201, 202 ] ) {
                    var result = variables.policy.classify( code );
                    expect( result.outcome ).toBe( "accepted" );
                    expect( result.reason ).toBe( "push-service-accepted" );
                    expect( result.retireSubscription ).toBeFalse();
                }
            } );
            it( "retires only confirmed expired subscriptions", () => {
                for ( var code in [ 404, 410 ] ) {
                    var result = variables.policy.classify( code );
                    expect( result.outcome ).toBe( "permanent" );
                    expect( result.retireSubscription ).toBeTrue();
                }
                expect( variables.policy.classify( 403 ).retireSubscription ).toBeFalse();
                expect( variables.policy.classify( 413 ).reason ).toBe( "push-payload-too-large" );
            } );
            it( "bounds numeric retry hints and supplies a safe default", () => {
                for ( var code in [ 429, 500, 503 ] ) {
                    var result = variables.policy.classify( code, "120", variables.clock );
                    expect( result.outcome ).toBe( "retryable" );
                    expect( dateDiff( "s", variables.clock, result.retryDate ) ).toBe( 120 );
                }
                expect(
                    dateDiff(
                        "s",
                        variables.clock,
                        variables.policy.classify( 429, "9999999999", variables.clock ).retryDate
                    )
                ).toBe( 86400 );
                expect(
                    dateDiff( "s", variables.clock, variables.policy.classify( 429, "0", variables.clock ).retryDate )
                ).toBe( 1 );
                expect(
                    dateDiff(
                        "s",
                        variables.clock,
                        variables.policy.classify( 503, "invalid", variables.clock ).retryDate
                    )
                ).toBe( 60 );
            } );
            it( "honors HTTP-date retry hints in UTC", () => {
                var result = variables.policy.classify( 503, "Mon, 5 Oct 2026 12:05:00 GMT", variables.clock );
                expect( dateDiff( "s", variables.clock, result.retryDate ) ).toBe( 300 );
            } );
            it( "keeps timeouts, redirects, and unexpected successes ambiguous", () => {
                for ( var code in [ 200, 204, 301, 307, 408 ] ) {
                    expect( variables.policy.classify( code ).outcome ).toBe( "ambiguous" );
                    expect( variables.policy.classify( code ).retireSubscription ).toBeFalse();
                }
            } );
            it( "rejects invalid response statuses", () => {
                for ( var code in [ 0, 99, 600, 201.5 ] ) {
                    expect( () => variables.policy.classify( code ) ).toThrow( type = "Megaphone.Push.InvalidResponse" );
                }
            } );
        } );
    }

}
