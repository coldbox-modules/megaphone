/** Resolving this expected source must never execute its component body. */
component {

    throw( type = "ExpectedSourceConstructed", message = "Expected source eligibility constructed a component." );

}
