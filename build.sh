#!/bin/bash

# BJJEasy - Flutter Build Script
# Gera o AAB para upload na Play Store

# INTERNAL_API_KEY do notification-server (espelha o que marcusjj/.env usa
# em WHATSAPP_API_KEY e EMAIL_API_KEY — mesmo valor para ambos canais).
NOTIFICATION_INTERNAL_KEY='c3d85c618a412a93034bd9cf6fcb20536fbd54cc73385ba6b369846ff87db119'

flutter build appbundle \
  --dart-define=APP_BASE_URL=https://bjjeasy.netlify.app \
  --dart-define=API_BASE_URL=https://bjjeasy.netlify.app/api \
  --dart-define=WHATSAPP_API_URL=https://notification.tensorroot.com/api/send-whatsapp \
  --dart-define=EMAIL_API_URL=https://notification.tensorroot.com/api/send-email \
  --dart-define=WHATSAPP_API_KEY="$NOTIFICATION_INTERNAL_KEY" \
  --dart-define=EMAIL_API_KEY="$NOTIFICATION_INTERNAL_KEY" \
  --dart-define=NOTIFICATION_API_KEY="$NOTIFICATION_INTERNAL_KEY" \
  --dart-define=NOTIFICATION_BULK_API_URL=https://notification.tensorroot.com/api/send-bulk
