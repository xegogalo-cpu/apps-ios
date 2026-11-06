package ec.enmarcha.red;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

/** Recibe los avisos de Firebase y los muestra como notificaciones de "En Marcha". */
public class AvisosService extends FirebaseMessagingService {

    static final String CANAL = "avisos";

    static void crearCanal(Context c) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel canal = new NotificationChannel(CANAL, "Avisos de En Marcha",
                    NotificationManager.IMPORTANCE_HIGH);
            canal.setDescription("Comunicados, llamados, tareas y convocatorias");
            NotificationManager nm = c.getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(canal);
        }
    }

    @Override
    public void onNewToken(String token) {
        getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE).edit().putString("token", token).apply();
    }

    // Con la app abierta (o avisos solo de datos) Firebase no muestra la notificación: se arma aquí.
    @Override
    public void onMessageReceived(RemoteMessage mensaje) {
        String titulo = "En Marcha";
        String cuerpo = "";
        RemoteMessage.Notification n = mensaje.getNotification();
        if (n != null) {
            if (n.getTitle() != null) titulo = n.getTitle();
            if (n.getBody() != null) cuerpo = n.getBody();
        } else {
            if (mensaje.getData().get("title") != null) titulo = mensaje.getData().get("title");
            if (mensaje.getData().get("body") != null) cuerpo = mensaje.getData().get("body");
        }
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return;
        }
        crearCanal(this);

        Intent abrir = new Intent(this, MainActivity.class);
        abrir.putExtra("ruta", mensaje.getData().get("ruta"));
        abrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int id = (int) (System.currentTimeMillis() % 100000);
        PendingIntent pi = PendingIntent.getActivity(this, id, abrir,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CANAL)
                : new Notification.Builder(this);
        b.setSmallIcon(R.drawable.ic_aviso)
                .setContentTitle(titulo)
                .setContentText(cuerpo)
                .setStyle(new Notification.BigTextStyle().bigText(cuerpo))
                .setColor(0xFFE0533D)
                .setAutoCancel(true)
                .setContentIntent(pi);
        if (Build.VERSION.SDK_INT < 26) {
            b.setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL);
        }
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(id, b.build());
    }
}
