#!/bin/bash

# BJJEasy - Flutter Build Script
# Gera o AAB para upload na Play Store

flutter build appbundle \
  --dart-define=APP_BASE_URL=https://bjjeasy.netlify.app \
  --dart-define=API_BASE_URL=https://bjjeasy.netlify.app/api \
  --dart-define=WHATSAPP_API_URL=https://notification.tensorroot.com/api/send-whatsapp \
  --dart-define=EMAIL_API_URL=https://notification.tensorroot.com/api/send-email \
  --dart-define=NOTIFICATION_API_KEY=JxqiatrOhLxW93ckSpJTtp9eo6k+pfQZs/bycwDqPJ0= \
  --dart-define=NOTIFICATION_BULK_API_URL=https://notification.tensorroot.com/api/send-bulk
