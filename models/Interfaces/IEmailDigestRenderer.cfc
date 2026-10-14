interface displayName="IEmailDigestRenderer" {

    /**
     * Renders current domain content with an unsubscribe link for this named digest.
     * @returns BaseNotification
     */
    public BaseNotification function render(
        required any notifiable,
        required struct definition,
        required struct batch,
        required array items
    );

}
