// Service worker de Firebase Cloud Messaging: muestra las notificaciones push con la app cerrada.
// La configuración web de Firebase es pública (no es un secreto); la seguridad la dan las reglas.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAW8nrx909fTuCnu2hblhr3_deg-ezHdPQ',
  appId: '1:988106397716:web:da5dd16f6ed38741c3ef01',
  messagingSenderId: '988106397716',
  projectId: 'woowfy-app',
  authDomain: 'woowfy-app.firebaseapp.com',
  storageBucket: 'woowfy-app.firebasestorage.app',
});

// Con `notification` en el mensaje, el SDK muestra la notificación solo y al tocarla abre `fcmOptions.link`.
firebase.messaging();
