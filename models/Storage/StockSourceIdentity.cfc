/** Lightweight source eligibility; every cache belongs to one operation. */
component {

    variables.expectedSourcePaths = {};
    variables.canonicalSourcePaths = {};
    variables.sourceIdentities = createObject( "java", "java.util.IdentityHashMap" ).init();

    /** A mapping alias may rename the same stock component; subclasses still have different source files. */
    public boolean function isStockComponent( required any instance, required string mapping ) {
        var identity = sourceIdentity( arguments.instance );
        if ( !structKeyExists( identity, arguments.mapping ) ) {
            identity[ arguments.mapping ] = isStockSource( arguments.instance, arguments.mapping );
        }
        return identity[ arguments.mapping ];
    }

    private struct function sourceIdentity( required any instance ) {
        if ( !variables.sourceIdentities.containsKey( arguments.instance ) ) {
            variables.sourceIdentities.put( arguments.instance, {} );
        }
        return variables.sourceIdentities.get( arguments.instance );
    }

    private struct function componentMetadata( required any instance ) {
        var identity = sourceIdentity( arguments.instance );
        if ( !structKeyExists( identity, "metadata" ) ) {
            identity.metadata = getMetadata( arguments.instance );
        }
        return identity.metadata;
    }

    /** Native BoxLang exposes the same source path without allocating full component metadata. */
    private string function componentSourcePath( required any instance ) {
        var identity = sourceIdentity( arguments.instance );
        if ( !structKeyExists( identity, "path" ) ) {
            if ( !structKeyExists( variables, "nativePathAvailable" ) ) {
                variables.nativePathAvailable = structKeyExists( server, "boxlang" );
            }
            if ( variables.nativePathAvailable ) {
                try {
                    if ( !structKeyExists( variables, "runnablePathMethod" ) ) {
                        variables.runnableClass = createObject( "java", "java.lang.Class" ).forName( "ortus.boxlang.runtime.runnables.IBoxRunnable" );
                        variables.runnablePathMethod = variables.runnableClass.getMethod(
                            "getRunnablePath",
                            javacast( "java.lang.Class[]", [] )
                        );
                    }
                    if ( variables.runnableClass.isInstance( arguments.instance ) ) {
                        identity.path = variables.runnablePathMethod
                            .invoke( arguments.instance, javacast( "java.lang.Object[]", [] ) )
                            .absolutePath()
                            .toString();
                    }
                } catch ( any unavailableNativePath ) {
                    // Older kernels and different classloaders retain the portable metadata boundary.
                    variables.nativePathAvailable = false;
                }
            }
            if (
                !structKeyExists( identity, "path" ) && structKeyExists( server, "lucee" ) && isCustomFunction(
                    arguments.instance
                )
            ) {
                try {
                    if ( !structKeyExists( variables, "udfPageSourceMethod" ) ) {
                        variables.udfClass = createObject( "java", "java.lang.Class" ).forName( "lucee.runtime.type.UDF" );
                        variables.udfPageSourceMethod = variables.udfClass.getMethod(
                            "getPageSource",
                            javacast( "java.lang.Class[]", [] )
                        );
                    }
                    if ( variables.udfClass.isInstance( arguments.instance ) ) {
                        identity.path = variables.udfPageSourceMethod
                            .invoke( arguments.instance, javacast( "java.lang.Object[]", [] ) )
                            .getPhyscalFile()
                            .getCanonicalPath();
                    }
                } catch ( any unavailableFunctionSource ) {
                    // Unprovable callback ownership must retain the generic compiler.
                }
            }
            if ( !structKeyExists( identity, "path" ) ) {
                // Function annotations cannot prove declaring ownership on an unknown engine.
                identity.path = isCustomFunction( arguments.instance ) ? "" : (
                    componentMetadata( arguments.instance ).path ?: ""
                );
            }
        }
        return identity.path;
    }

    private boolean function isStockSource( required any instance, required string mapping ) {
        var path = componentSourcePath( arguments.instance );
        if ( !len( path ) ) {
            return false;
        }
        if ( !structKeyExists( variables.expectedSourcePaths, arguments.mapping ) ) {
            var expectedPath = mappedSourcePath( arguments.mapping );
            if ( !len( expectedPath ) ) {
                return false;
            }
            variables.expectedSourcePaths[ arguments.mapping ] = canonicalSourcePath( expectedPath );
        }
        return compare( canonicalSourcePath( path ), variables.expectedSourcePaths[ arguments.mapping ] ) == 0;
    }

    /** Resolve a fixed stock mapping to its existing file without constructing or compiling that class. */
    private string function mappedSourcePath( required string mapping ) {
        if ( !structKeyExists( variables, "nativeResolverAvailable" ) ) {
            variables.nativeResolverAvailable = structKeyExists( server, "boxlang" );
        }
        if ( variables.nativeResolverAvailable ) {
            try {
                if ( !structKeyExists( variables, "boxResolver" ) ) {
                    variables.boxResolver = createObject( "java", "ortus.boxlang.runtime.loader.ClassLocator" )
                        .getInstance()
                        .getBoxResolver();
                    variables.emptyImports = createObject( "java", "java.util.Collections" ).emptyList();
                }
                var location = variables.boxResolver.resolve(
                    getBoxContext(),
                    arguments.mapping,
                    variables.emptyImports
                );
                if ( !location.isPresent() ) {
                    return "";
                }
                var resolved = location
                    .get()
                    .resolvedFilePath()
                    .absolutePath()
                    .toString();
                return fileExists( resolved ) ? resolved : "";
            } catch ( any unavailableNativeResolver ) {
                // Other kernels/classloaders retain mapping-aware filesystem resolution, never class construction.
                variables.nativeResolverAvailable = false;
            }
        }
        try {
            var expected = expandPath( "/" & replace( arguments.mapping, ".", "/", "all" ) & ".cfc" );
            return fileExists( expected ) ? expected : "";
        } catch ( any unresolvedMappedFile ) {
            return "";
        }
    }

    private string function canonicalSourcePath( required string path ) {
        if ( !structKeyExists( variables.canonicalSourcePaths, arguments.path ) ) {
            variables.canonicalSourcePaths[ arguments.path ] = createObject( "java", "java.io.File" )
                .init( arguments.path )
                .getCanonicalPath();
        }
        return variables.canonicalSourcePaths[ arguments.path ];
    }

    /** Only qb's public executor with the unmodified PostgreSQL compiler supports this opt-in path. */
    public boolean function supportsReturning( required any query ) {
        if ( !isStockComponent( arguments.query, "qb.models.Query.QueryBuilder" ) ) {
            return false;
        }
        var grammar = arguments.query.getGrammar();
        if ( isCustomFunction( grammar.getResolvedGrammar ?: "" ) ) {
            grammar = grammar.getResolvedGrammar();
        }
        if ( !isStockComponent( grammar, "qb.models.Grammars.PostgresGrammar" ) ) {
            return false;
        }
        try {
            return isCustomFunction( arguments.query.runQuery ) && compareNoCase(
                getMetadata( arguments.query.runQuery ).access ?: "",
                "public"
            ) == 0;
        } catch ( any inaccessibleExecutor ) {
            // qb 9's executor is private; preserve its existing generic store path.
            return false;
        }
    }

    /** QB14 always supplies its private identity callback, even without custom formatting. */
    public boolean function hasIdentityColumnFormatter( required any query ) {
        var formatter = arguments.query.getColumnFormatter();
        if ( isNull( formatter ) || !isCustomFunction( formatter ) || isClosure( formatter ) ) {
            return false;
        }
        var metadata = componentMetadata( formatter );
        return compareNoCase( metadata.name ?: "", "identityColumnFormatter" ) == 0 && compareNoCase(
            metadata.access ?: "",
            "private"
        ) == 0 && isStockComponent( formatter, "qb.models.Query.QueryBuilder" );
    }

}
