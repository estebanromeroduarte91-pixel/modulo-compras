#!/bin/bash
# Servidor local para el ERP modulo-compras
cd "$(dirname "$0")"
echo "======================================="
echo "  ERP modulo-compras — Servidor local"
echo "======================================="
echo ""
echo "  Abre en Chrome: http://localhost:8080"
echo ""
echo "  (Cierra esta ventana para detenerlo)"
echo "======================================="
python3 -m http.server 8080
