import { fileURLToPath, URL } from 'node:url';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { defineConfig, type Plugin } from 'vite';
import plugin from '@vitejs/plugin-vue';

// 开发/预览服务器里 /admin 不会自动解析到 admin/index.html，
// 会被 SPA 回退兜底成官网首页；补一个结尾斜杠后再交给 Vite 处理。
function adminTrailingSlash(): Plugin {
    const middleware = (
        req: IncomingMessage,
        _res: ServerResponse,
        next: () => void,
    ) => {
        const url = req.url ?? '';
        if (url === '/admin' || url.startsWith('/admin?')) {
            req.url = url.replace(/^\/admin/, '/admin/');
        }
        next();
    };
    return {
        name: 'raillog-admin-trailing-slash',
        configureServer(server) {
            server.middlewares.use(middleware);
        },
        configurePreviewServer(server) {
            server.middlewares.use(middleware);
        },
    };
}

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [plugin(), adminTrailingSlash()],
    server: {
        port: 55634,
        proxy: {
            '^/api/': 'http://localhost:5149',
        },
    },
    build: {
        rollupOptions: {
            input: {
                main: fileURLToPath(new URL('./index.html', import.meta.url)),
                admin: fileURLToPath(new URL('./admin/index.html', import.meta.url)),
            },
        },
    },
})
