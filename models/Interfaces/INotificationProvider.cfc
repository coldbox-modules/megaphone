interface displayName="INotificationProvider" {

    public string function getProviderName();
    public BaseNotification function notify( required any notifiable, required BaseNotification notification );

}
