const CACHE = "mm-ledger-v2";

self.addEventListener("install", e => {
    e.waitUntil(
        caches.open(CACHE).then(cache => {
            return cache.addAll([
                "/",
                "/static/style.css",
                "/static/script.js"
            ]);
        })
    );
});

self.addEventListener("activate", e => {
    e.waitUntil(
        caches.keys().then(keys => {
            return Promise.all(
                keys.map(key => {
                    if (key !== CACHE) {
                        return caches.delete(key);
                    }
                })
            );
        })
    );
});

self.addEventListener("fetch", e => {
    const url = new URL(e.request.url);
    const isApiRequest = url.pathname.startsWith('/get_') || 
                        url.pathname.startsWith('/total_') || 
                        url.pathname.startsWith('/add_') ||
                        url.pathname.startsWith('/update_') ||
                        url.pathname.startsWith('/delete_') ||
                        url.pathname.startsWith('/summary') ||
                        url.pathname.startsWith('/expense_') ||
                        url.pathname.startsWith('/expenses_');

    if (isApiRequest) {
        // Network-first strategy for API endpoints
        e.respondWith(
            fetch(e.request)
                .then(res => {
                    if (res.ok) {
                        const resClone = res.clone();
                        caches.open(CACHE).then(cache => {
                            cache.put(e.request, resClone);
                        });
                    }
                    return res;
                })
                .catch(() => {
                    return caches.match(e.request)
                        .then(res => res || new Response('Offline'));
                })
        );
    } else {
        // Cache-first for static assets
        e.respondWith(
            caches.match(e.request).then(res => res || fetch(e.request))
        );
    }
});