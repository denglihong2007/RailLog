import { defineConfig } from 'vite';
import plugin from '@vitejs/plugin-vue';

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [plugin()],
    server: {
        port: 55634,
        proxy: {
            '/api': 'http://localhost:5149',
        },
    }
})
