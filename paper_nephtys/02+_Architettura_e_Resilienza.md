# II. Architettura del Sistema e Resilienza

L'architettura di Nephtys è progettata specificamente per i vincoli dell'Edge Computing (basso consumo di risorse e connettività instabile).

**A. Ingestione Tollerante ai Guasti**
L'astrazione dei connettori (es. `WebSocketSource`) implementa nativamente meccanismi di resilienza. In caso di perdita di connettività, il sistema non si arresta, ma innesca una routine di riconnessione automatica basata su un algoritmo di *exponential backoff*, prevenendo attacchi DDoS non intenzionali verso i provider dei dati o la rete locale.

**B. Persistenza Zero-Infrastructure**
Per garantire la sopravvivenza dei dati ai riavvii hardware senza gravare l'edge con database SQL esterni, Nephtys sfrutta esclusivamente NATS JetStream. Le configurazioni dei flussi attivi sono serializzate in un *JetStream KV bucket*, consentendo un ripristino istantaneo dello stato.

**C. Edge-Pipeline per la Riduzione della Banda**
Il cuore innovativo è il motore di *Pipeline Middlewares*. Prima che un evento venga pubblicato sul broker, attraversa una catena di trasformazione configurabile. Il middleware `Dedup` calcola l'hash FNV-64a del payload e blocca i messaggi duplicati all'interno di una finestra temporale (es. letture ridondanti di un sensore). Il middleware `Transform` estrae solo i campi rilevanti da JSON profondamente annidati tramite *dot-notation*, appiattendo il payload. Questa elaborazione asimmetrica sposta il carico computazionale sull'edge, trasmettendo al cloud solo informazioni dense e non ridondanti.