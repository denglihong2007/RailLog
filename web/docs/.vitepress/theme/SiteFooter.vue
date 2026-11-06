<script setup lang="ts">
import { withBase } from 'vitepress'
</script>

<template>
    <footer class="rl-site-footer">
        <div class="rl-footer-brand">
            <img :src="withBase('/raillog-icon.png')" alt="" />
            <span>RailLog 轨记</span>
        </div>
        <p>GNU General Public License v3.0</p>
        <a href="https://github.com/denglihong2007/RailLog" target="_blank" rel="noreferrer">
            查看源代码 <span aria-hidden="true">→</span>
        </a>
    </footer>
</template>
