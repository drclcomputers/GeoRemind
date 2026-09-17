**Roadmap tehnic — GeoRemind**

**2. Sync cloud**
- Migrare SwiftData → CloudKit (`NSPersistentCloudKitContainer` sau SwiftData+CloudKit nativ, iOS 17+)
- Sincronizare automată între dispozitivele aceluiași Apple ID
- Gestionare conflicte (merge policy pentru editări simultane)
- Opțional: backend separat (Firebase/Supabase) dacă vrei login cross-platform (email+parolă, Google, Android viitor) dar cred ca ar fi util să facem asta

**3. Autentificare/profil**
- Sign in with Apple (cel mai simplu, integrare nativă)
- Model de user/profil local + sincronizat
- Setări per-cont (preferințe notificări, unități de măsură etc.)

**4. Partajare / grupuri**
- CloudKit Shared Zones pentru partajare pin-uri/liste între conturi
- Model de roluri (owner/member, editare vs. doar vizualizare)
- Link de invitație pentru alăturare la grup
- UI pentru gestionare membri și pin-uri comune

**5. Optimizări geofencing**
- Monitorizare eficientă a bateriei (throttling pe `significant location change` vs GPS continuu)
- Fallback pentru regiuni foarte apropiate geografic (evitare triggere false)
- scăzut radius de la 50 la 10m. Gps ul are în ziua de azi precizie de 2-3m deci 10 e chiar bine zic.

**6. Funcționalități suplimentare**
- Reminder-uri recurente (ex: „în fiecare zi de luni când ajung la birou" sau de fiecare dată când trec la ora 14 prin față la magazin să intru să salut pe cineva)
- Integrare Siri Shortcuts („adaugă reminder la locația curentă") (opțional)
- Export/import reminder-uri (JSON/CSV) (poate ceva bază de date sau tip de fișier propriu, dar opțional )

**7. Infrastructură/calitate cod**
- Suite de teste unitare (mai ales pentru `GeofenceManagerServ`)
- CI/CD (GitHub Actions pentru build+test automat)
- Crash reporting (Firebase Crashlytics sau Sentry)
- Analiză consum baterie/precizie pe device real, documentată

Nu trebuie să facem nimic acum. E doar un roadmap.
