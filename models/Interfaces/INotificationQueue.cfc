/** Queues saved delivery references for later dispatch through Megaphone. */
interface displayName="INotificationQueue" {

    /**
     * Enqueues a saved delivery using optional connection and queue overrides.
     * Omitting either override leaves its selection to the adapter's defaults.
     * @delivery The persisted delivery to dispatch later.
     * @connection The queue connection override, when supplied.
     * @queue The queue name override, when supplied.
     */
    public void function enqueue(
        required megaphone.models.NotificationDelivery delivery,
        string connection,
        string queue
    );

}
