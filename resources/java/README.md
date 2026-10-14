# Web Push SDK

Megaphone depends on `com.zerodeplibs:zerodep-web-push-java:2.1.5` (MIT), using its
JDK HTTP client. No additional runtime libraries or fat JAR are required.

Source: https://github.com/st-user/zerodep-web-push-java

SHA-256: `1337acba24004f2a702275b676eb3862e402c8775d3031b26464f0b18d3ba989`

The module's `box.json` declares the pinned URL using CommandBox's JAR endpoint
and installs it into `webpush/`. Run `box install` to install it alongside
the other dependencies. The runtime checks its checksum before loading it.
The downloaded JAR is not committed to Git or copied into the publisher archive;
its license is included as `webpush-LICENSE.txt` in the module package.

On Adobe ColdFusion, add the installed SDK folder to your application's Java classpath in `Application.cfc`, alongside any existing `loadPaths`:

```js
this.javaSettings = {
    "loadPaths": [ "./modules/megaphone/resources/java/webpush" ],
    "loadColdFusionClassPath": true
};
```

Adjust the path if your application installs modules elsewhere. Megaphone still verifies the SDK checksum before using it.
