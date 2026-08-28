const CACHE_NAME = "mm-lifecare-v3";

const urlsToCache = [
    "/",
    "/static/style.css",
    "/static/script.js"
];

// Install
self.addEventListener("install", event => {
    event.waitUntil(
        caches.open(CACHE_NAME).then(cache => {
            return cache.addAll(urlsToCache);
        })
    );
});

// Activate
self.addEventListener("activate", event => {
    event.waitUntil(
        caches.keys().then(keys => {
            return Promise.all(
                keys.map(key => {
                    if (key !== CACHE_NAME) {
                        return caches.delete(key);
                    }
                })
            );
        })
    );
});

// Fetch - Use different strategies for API vs static assets
self.addEventListener("fetch", event => {
    const url = new URL(event.request.url);
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
        event.respondWith(
            fetch(event.request)
                .then(response => {
                    // Cache the response for offline use only
                    if (response.ok) {
                        const responseClone = response.clone();
                        caches.open(CACHE_NAME).then(cache => {
                            cache.put(event.request, responseClone);
                        });
                    }
                    return response;
                })
                .catch(() => {
                    // If network fails, try cache (for offline support)
                    return caches.match(event.request)
                        .then(response => response || new Response('Offline'));
                })
        );
    } else {
        // Cache-first strategy for static assets
        event.respondWith(
            caches.match(event.request).then(response => {
                return response || fetch(event.request);
            })
        );
    }
});