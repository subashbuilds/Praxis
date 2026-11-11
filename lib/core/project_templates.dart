import '../models.dart';

/// A starter project that can be created without a network request. Each
/// runtime keeps its templates together so Home can reveal them only after the
/// runtime itself is expanded.
enum TemplateRuntime { node, python, php, go }

extension TemplateRuntimeX on TemplateRuntime {
  String get label => switch (this) {
        TemplateRuntime.node => 'Node.js',
        TemplateRuntime.python => 'Python',
        TemplateRuntime.php => 'PHP',
        TemplateRuntime.go => 'Go',
      };

  ProjectKind get kind => switch (this) {
        TemplateRuntime.node => ProjectKind.node,
        TemplateRuntime.python => ProjectKind.python,
        TemplateRuntime.php => ProjectKind.php,
        TemplateRuntime.go => ProjectKind.go,
      };
}

class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.runtime,
    required this.description,
    required this.files,
  });

  final String id;
  final String name;
  final TemplateRuntime runtime;
  final String description;
  final Map<String, String> files;

  ProjectKind get kind => runtime.kind;
}

List<ProjectTemplate> templatesFor(TemplateRuntime runtime) =>
    kProjectTemplates.where((template) => template.runtime == runtime).toList();

const kProjectTemplates = <ProjectTemplate>[
  ProjectTemplate(
    id: 'react',
    name: 'React',
    runtime: TemplateRuntime.node,
    description: 'Vite + React with a small interactive starting page.',
    files: {
      'package.json': '''{
  "name": "praxis-react",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@vitejs/plugin-react": "latest",
    "vite": "latest",
    "react": "latest",
    "react-dom": "latest"
  },
  "devDependencies": {}
}
''',
      'vite.config.js': '''import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({ plugins: [react()] });
''',
      'index.html': '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>React on Praxis</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
''',
      'src/main.jsx': '''import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

createRoot(document.getElementById('root')).render(
  <React.StrictMode><App /></React.StrictMode>,
);
''',
      'src/App.jsx': r'''import { useState } from 'react';

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <main>
      <p className="eyebrow">PRAXIS · REACT</p>
      <h1>Start with a real component.</h1>
      <p>Edit <code>src/App.jsx</code>, then refresh the preview.</p>
      <button onClick={() => setCount(count + 1)}>
        {count === 0 ? 'Tap me' : `${count} taps`}
      </button>
    </main>
  );
}
''',
      'src/styles.css': '''* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: #f7f3ec;
  color: #1c1916;
  font-family: system-ui, sans-serif;
}
main { width: min(88vw, 460px); }
.eyebrow { color: #c0512c; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: clamp(32px, 8vw, 52px); line-height: 1.04; margin: 10px 0 16px; }
p { color: #5e564d; line-height: 1.6; }
button {
  margin-top: 14px; padding: 13px 20px; border-radius: 12px;
  border: 0; background: #c0512c; color: #fff8f3; font-weight: 700;
}
''',
      'README.md': '''# React on Praxis

A Vite + React starter for the Node.js runtime.

```sh
npm install
npm run dev
```

The preview tab detects the built `dist/index.html`.
''',
    },
  ),
  ProjectTemplate(
    id: 'react-tailwind',
    name: 'React + Tailwind',
    runtime: TemplateRuntime.node,
    description: 'Vite, React and Tailwind CSS with a responsive hero.',
    files: {
      'package.json': '''{
  "name": "praxis-react-tailwind",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@vitejs/plugin-react": "latest",
    "vite": "latest",
    "react": "latest",
    "react-dom": "latest",
    "tailwindcss": "^3.4.0",
    "postcss": "latest",
    "autoprefixer": "latest"
  }
}
''',
      'vite.config.js': '''import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({ plugins: [react()] });
''',
      'tailwind.config.js': '''/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: { extend: { colors: { ember: '#c0512c' } } },
  plugins: [],
};
''',
      'postcss.config.js':
          '''export default { plugins: { tailwindcss: {}, autoprefixer: {} } };
''',
      'index.html': '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>React + Tailwind on Praxis</title>
  </head>
  <body class="bg-stone-50 text-stone-900 antialiased">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
''',
      'src/main.jsx': '''import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './index.css';

createRoot(document.getElementById('root')).render(
  <React.StrictMode><App /></React.StrictMode>,
);
''',
      'src/index.css': '''@tailwind base;
@tailwind components;
@tailwind utilities;
''',
      'src/App.jsx': '''export default function App() {
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <section className="w-full max-w-xl rounded-3xl border border-stone-200 bg-white p-8 shadow-sm">
        <p className="text-xs font-bold uppercase tracking-[0.25em] text-ember">Praxis · Tailwind</p>
        <h1 className="mt-4 text-5xl font-semibold leading-none tracking-tight">Utility-first from the first file.</h1>
        <p className="mt-5 leading-7 text-stone-600">Tailwind is wired through PostCSS. Edit the classes in App.jsx and the preview updates.</p>
        <button className="mt-7 rounded-xl bg-ember px-5 py-3 font-semibold text-white">Build something small</button>
      </section>
    </main>
  );
}
''',
      'README.md': '''# React + Tailwind on Praxis

```sh
npm install
npm run dev
```
''',
    },
  ),
  ProjectTemplate(
    id: 'vue',
    name: 'Vue',
    runtime: TemplateRuntime.node,
    description: 'Vite + Vue single-file components.',
    files: {
      'package.json': '''{
  "name": "praxis-vue",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "vue": "latest",
    "vite": "latest",
    "@vitejs/plugin-vue": "latest"
  }
}
''',
      'vite.config.js': '''import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({ plugins: [vue()] });
''',
      'index.html': '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Vue on Praxis</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.js"></script>
  </body>
</html>
''',
      'src/main.js': '''import { createApp } from 'vue';
import App from './App.vue';
import './style.css';

createApp(App).mount('#app');
''',
      'src/App.vue': '''<script setup>
import { ref } from 'vue';
const count = ref(0);
</script>

<template>
  <main>
    <p class="eyebrow">PRAXIS · VUE</p>
    <h1>Reactive by default.</h1>
    <p>Edit <code>src/App.vue</code>, then refresh the preview.</p>
    <button @click="count++">{{ count || 'Tap me' }}{{ count ? ' taps' : '' }}</button>
  </main>
</template>
''',
      'src/style.css': '''* { box-sizing: border-box; }
body {
  margin: 0; min-height: 100vh; display: grid; place-items: center;
  background: #f7f3ec; color: #1c1916; font-family: system-ui, sans-serif;
}
main { width: min(88vw, 440px); }
.eyebrow { color: #267354; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: clamp(32px, 8vw, 50px); line-height: 1.05; margin: 10px 0 16px; }
p { color: #5e564d; line-height: 1.6; }
button { margin-top: 14px; padding: 13px 20px; border: 0; border-radius: 12px; background: #267354; color: white; font-weight: 700; }
''',
      'README.md': '''# Vue on Praxis

```sh
npm install
npm run dev
```
''',
    },
  ),
  ProjectTemplate(
    id: 'svelte',
    name: 'Svelte',
    runtime: TemplateRuntime.node,
    description: 'Vite + Svelte with a tiny reactive counter.',
    files: {
      'package.json': '''{
  "name": "praxis-svelte",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "svelte": "latest",
    "vite": "latest",
    "@sveltejs/vite-plugin-svelte": "latest"
  }
}
''',
      'vite.config.js': '''import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({ plugins: [svelte()] });
''',
      'svelte.config.js': '''export default {};
''',
      'index.html': '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Svelte on Praxis</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.js"></script>
  </body>
</html>
''',
      'src/main.js': '''import { mount } from 'svelte';
import App from './App.svelte';
import './style.css';

mount(App, { target: document.getElementById('app') });
''',
      'src/App.svelte': '''<script>
  let count = 0;
</script>

<main>
  <p class="eyebrow">PRAXIS · SVELTE</p>
  <h1>Small framework. Real components.</h1>
  <p>Edit <code>src/App.svelte</code>, then refresh the preview.</p>
  <button on:click={() => count++}>{count || 'Tap me'}{count ? ' taps' : ''}</button>
</main>
''',
      'src/style.css': '''* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #fff7f2; color: #1c1916; font-family: system-ui, sans-serif; }
main { width: min(88vw, 440px); }
.eyebrow { color: #b23b36; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: clamp(32px, 8vw, 50px); line-height: 1.05; margin: 10px 0 16px; }
p { color: #5e564d; line-height: 1.6; }
button { margin-top: 14px; padding: 13px 20px; border: 0; border-radius: 12px; background: #b23b36; color: white; font-weight: 700; }
''',
      'README.md': '''# Svelte on Praxis

```sh
npm install
npm run dev
```
''',
    },
  ),
  ProjectTemplate(
    id: 'next',
    name: 'Next.js',
    runtime: TemplateRuntime.node,
    description: 'Next.js App Router with a server-rendered landing page.',
    files: {
      'package.json': '''{
  "name": "praxis-next",
  "private": true,
  "scripts": {
    "dev": "next dev --hostname 0.0.0.0",
    "build": "next build",
    "start": "next start --hostname 0.0.0.0"
  },
  "dependencies": {
    "next": "latest",
    "react": "latest",
    "react-dom": "latest"
  }
}
''',
      'next.config.mjs': '''/** @type {import('next').NextConfig} */
const nextConfig = {};
export default nextConfig;
''',
      'jsconfig.json': '''{ "compilerOptions": { "paths": { "@/*": ["./*"] } } }
''',
      'app/layout.js': '''import './globals.css';

export const metadata = { title: 'Next.js on Praxis' };

export default function RootLayout({ children }) {
  return (
    <html lang="en"><body>{children}</body></html>
  );
}
''',
      'app/page.js': '''export default function Page() {
  return (
    <main>
      <p className="eyebrow">PRAXIS · NEXT.JS</p>
      <h1>The App Router, on your phone.</h1>
      <p>Edit <code>app/page.js</code>, then refresh the preview.</p>
    </main>
  );
}
''',
      'app/globals.css': '''* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0a0908; color: #f4efe9; font-family: system-ui, sans-serif; }
main { width: min(88vw, 460px); }
.eyebrow { color: #8ab4f0; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: clamp(32px, 8vw, 54px); line-height: 1.04; margin: 10px 0 16px; }
p { color: #b7ada2; line-height: 1.6; }
''',
      'README.md': '''# Next.js on Praxis

```sh
npm install
npm run dev
```
''',
    },
  ),
  ProjectTemplate(
    id: 'nuxt',
    name: 'Nuxt',
    runtime: TemplateRuntime.node,
    description: 'Nuxt 3 with pages and a Vue welcome screen.',
    files: {
      'package.json': '''{
  "name": "praxis-nuxt",
  "private": true,
  "scripts": {
    "dev": "nuxt dev --host 0.0.0.0",
    "build": "nuxt build",
    "preview": "nuxt preview"
  },
  "dependencies": { "nuxt": "latest" }
}
''',
      'nuxt.config.ts': '''export default defineNuxtConfig({
  devtools: { enabled: false },
  app: { head: { title: 'Nuxt on Praxis' } },
});
''',
      'app.vue': '''<template><NuxtPage /></template>
''',
      'pages/index.vue': '''<template>
  <main>
    <p class="eyebrow">PRAXIS · NUXT</p>
    <h1>Pages, auto-imported.</h1>
    <p>Edit <code>pages/index.vue</code>, then refresh the preview.</p>
  </main>
</template>

<style>
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0b1712; color: #effcf5; font-family: system-ui, sans-serif; }
main { width: min(88vw, 460px); }
.eyebrow { color: #7fd1a8; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: clamp(32px, 8vw, 54px); line-height: 1.04; margin: 10px 0 16px; }
p { color: #acd7c4; line-height: 1.6; }
</style>
''',
      'README.md': '''# Nuxt on Praxis

```sh
npm install
npm run dev
```
''',
    },
  ),
  ProjectTemplate(
    id: 'express',
    name: 'Express.js',
    runtime: TemplateRuntime.node,
    description: 'A minimal Express JSON API with one route.',
    files: {
      'package.json': '''{
  "name": "praxis-express",
  "private": true,
  "type": "module",
  "scripts": { "start": "node server.js" },
  "dependencies": { "express": "latest" }
}
''',
      'server.js': r'''import express from 'express';

const app = express();
app.use(express.json());

app.get('/', (_req, res) => {
  res.type('html').send('<h1>Express on Praxis</h1><p>Try <a href="/api/hello">/api/hello</a>.</p>');
});

app.get('/api/hello', (_req, res) => {
  res.json({ message: 'hello from Praxis', at: new Date().toISOString() });
});

const port = process.env.PORT || 3000;
app.listen(port, '0.0.0.0', () => console.log(`http://localhost:${port}`));
''',
      'README.md': '''# Express.js on Praxis

```sh
npm install
npm start
```

The Preview tab looks for an HTML entry point. Use the Shell for this API and
open `/api/hello` through a curl command.
''',
    },
  ),
  ProjectTemplate(
    id: 'nestjs',
    name: 'NestJS',
    runtime: TemplateRuntime.node,
    description: 'A typed NestJS service, controller and module.',
    files: {
      'package.json': '''{
  "name": "praxis-nest",
  "private": true,
  "scripts": {
    "start": "ts-node src/main.ts",
    "build": "tsc -p tsconfig.json"
  },
  "dependencies": {
    "@nestjs/common": "latest",
    "@nestjs/core": "latest",
    "@nestjs/platform-express": "latest",
    "reflect-metadata": "latest",
    "rxjs": "latest"
  },
  "devDependencies": { "ts-node": "latest", "typescript": "latest" }
}
''',
      'tsconfig.json': '''{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2022",
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist"
  },
  "include": ["src/**/*.ts"]
}
''',
      'src/main.ts': '''import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  await app.listen(3000, '0.0.0.0');
  console.log('NestJS listening on http://localhost:3000');
}
bootstrap();
''',
      'src/app.module.ts': '''import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';

@Module({
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
''',
      'src/app.controller.ts':
          '''import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  root() { return this.appService.hello(); }
}
''',
      'src/app.service.ts': '''import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  hello() { return { message: 'hello from Praxis' }; }
}
''',
      'README.md': '''# NestJS on Praxis

```sh
npm install
npm start
```
''',
    },
  ),
  ProjectTemplate(
    id: 'discordjs',
    name: 'Discord.js',
    runtime: TemplateRuntime.node,
    description: 'A slash-command-ready Discord bot skeleton.',
    files: {
      'package.json': '''{
  "name": "praxis-discord-bot",
  "private": true,
  "type": "module",
  "scripts": { "start": "node index.js" },
  "dependencies": { "discord.js": "latest", "dotenv": "latest" }
}
''',
      'index.js': r'''import 'dotenv/config';
import { Client, Events, GatewayIntentBits } from 'discord.js';

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

client.once(Events.ClientReady, (ready) => {
  console.log(`Ready as ${ready.user.tag}`);
});

client.on(Events.InteractionCreate, async (interaction) => {
  if (!interaction.isChatInputCommand()) return;
  if (interaction.commandName === 'ping') {
    await interaction.reply('Pong from Praxis.');
  }
});

const token = process.env.DISCORD_TOKEN;
if (!token) {
  console.error('Set DISCORD_TOKEN in .env before starting the bot.');
  process.exit(1);
}
client.login(token);
''',
      '.env.example': '''DISCORD_TOKEN=replace-me
''',
      'README.md': '''# Discord.js on Praxis

Copy `.env.example` to `.env`, add your bot token, then:

```sh
npm install
npm start
```
''',
    },
  ),
  ProjectTemplate(
    id: 'expo',
    name: 'React Native (Expo)',
    runtime: TemplateRuntime.node,
    description: 'Expo app with a native-feeling first screen.',
    files: {
      'package.json': '''{
  "name": "praxis-expo",
  "private": true,
  "main": "node_modules/expo/AppEntry.js",
  "scripts": { "start": "expo start" },
  "dependencies": {
    "expo": "latest",
    "react": "latest",
    "react-native": "latest"
  }
}
''',
      'app.json': '''{
  "expo": {
    "name": "Praxis Expo",
    "slug": "praxis-expo",
    "version": "1.0.0",
    "orientation": "portrait"
  }
}
''',
      'babel.config.js': '''module.exports = function (api) {
  api.cache(true);
  return { presets: ['babel-preset-expo'] };
};
''',
      'App.js': r'''import { useState } from 'react';
import { Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.card}>
        <Text style={styles.eyebrow}>PRAXIS · EXPO</Text>
        <Text style={styles.title}>A native start.</Text>
        <Text style={styles.body}>Edit App.js and scan the QR code from the Expo CLI.</Text>
        <Pressable style={styles.button} onPress={() => setCount(count + 1)}>
          <Text style={styles.buttonText}>{count ? `${count} taps` : 'Tap me'}</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f7f3ec', justifyContent: 'center', padding: 24 },
  card: { backgroundColor: '#fff', borderRadius: 24, padding: 28 },
  eyebrow: { color: '#c0512c', fontWeight: '700', letterSpacing: 2, fontSize: 11 },
  title: { color: '#1c1916', fontSize: 38, fontWeight: '700', marginTop: 14 },
  body: { color: '#5e564d', fontSize: 16, lineHeight: 24, marginTop: 12 },
  button: { backgroundColor: '#c0512c', borderRadius: 12, padding: 14, marginTop: 22 },
  buttonText: { color: '#fff8f3', textAlign: 'center', fontWeight: '700' },
});
''',
      'README.md': '''# Expo on Praxis

```sh
npm install
npm start
```
''',
    },
  ),
  ProjectTemplate(
    id: 'django',
    name: 'Django',
    runtime: TemplateRuntime.python,
    description: 'Django project with a home view and URL routing.',
    files: {
      'requirements.txt': 'Django>=5.0,<6.0\n',
      'manage.py': '''#!/usr/bin/env python3
import os
import sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
''',
      'mysite/__init__.py': '',
      'mysite/settings.py': '''from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = "praxis-development-only"
DEBUG = True
ALLOWED_HOSTS = ["*"]
ROOT_URLCONF = "mysite.urls"
TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [BASE_DIR / "templates"],
    "APP_DIRS": True,
    "OPTIONS": {"context_processors": []},
}]
WSGI_APPLICATION = "mysite.wsgi.application"
DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}
INSTALLED_APPS = ["django.contrib.contenttypes", "django.contrib.staticfiles", "home"]
STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
''',
      'mysite/urls.py': '''from django.urls import include, path

urlpatterns = [path("", include("home.urls"))]
''',
      'mysite/wsgi.py': '''import os
from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")
application = get_wsgi_application()
''',
      'home/__init__.py': '',
      'home/urls.py': '''from django.urls import path
from . import views

urlpatterns = [path("", views.index, name="index")]
''',
      'home/views.py': '''from django.http import HttpResponse

def index(request):
    return HttpResponse("<h1>Django on Praxis</h1><p>Edit home/views.py to begin.</p>")
''',
      'README.md': '''# Django on Praxis

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8000
```
''',
    },
  ),
  ProjectTemplate(
    id: 'fastapi',
    name: 'FastAPI',
    runtime: TemplateRuntime.python,
    description: 'FastAPI app with a JSON endpoint and interactive docs.',
    files: {
      'requirements.txt': 'fastapi\nuvicorn[standard]\n',
      'app/__init__.py': '',
      'app/main.py': '''from fastapi import FastAPI

app = FastAPI(title="Praxis FastAPI")

@app.get("/")
def root():
    return {"message": "hello from Praxis"}

@app.get("/health")
def health():
    return {"ok": True}
''',
      'README.md': '''# FastAPI on Praxis

```sh
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Open `/docs` for the generated API documentation.
''',
    },
  ),
  ProjectTemplate(
    id: 'flask',
    name: 'Flask (Python)',
    runtime: TemplateRuntime.python,
    description: 'Flask app with a template and JSON route.',
    files: {
      'requirements.txt': 'Flask>=3.0\n',
      'app.py': '''from flask import Flask, jsonify, render_template

app = Flask(__name__)

@app.get("/")
def index():
    return render_template("index.html")

@app.get("/api/hello")
def hello():
    return jsonify(message="hello from Praxis")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
''',
      'templates/index.html': '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Flask on Praxis</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f7f3ec; color: #1c1916; font-family: system-ui, sans-serif; }
      main { width: min(88vw, 460px); }
      p { color: #c0512c; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
      h1 { font-size: clamp(32px, 8vw, 50px); line-height: 1.04; }
    </style>
  </head>
  <body><main><p>PRAXIS · FLASK</p><h1>Hello from a template.</h1></main></body>
</html>
''',
      'README.md': '''# Flask on Praxis

```sh
pip install -r requirements.txt
python app.py
```
''',
    },
  ),
  ProjectTemplate(
    id: 'aiogram',
    name: 'aiogram (Python)',
    runtime: TemplateRuntime.python,
    description: 'Async Telegram bot with a /start command.',
    files: {
      'requirements.txt': 'aiogram>=3.0\npython-dotenv\n',
      'bot.py': '''import asyncio
import os

from aiogram import Bot, Dispatcher
from aiogram.filters import CommandStart
from aiogram.types import Message
from dotenv import load_dotenv

load_dotenv()
dp = Dispatcher()

@dp.message(CommandStart())
async def start(message: Message):
    await message.answer("Hello from Praxis.")

async def main():
    token = os.getenv("BOT_TOKEN")
    if not token:
        raise SystemExit("Set BOT_TOKEN in .env first.")
    await dp.start_polling(Bot(token))

if __name__ == "__main__":
    asyncio.run(main())
''',
      '.env.example': 'BOT_TOKEN=replace-me\n',
      'README.md': '''# aiogram on Praxis

Copy `.env.example` to `.env`, add the token from BotFather, then:

```sh
pip install -r requirements.txt
python bot.py
```
''',
    },
  ),
  ProjectTemplate(
    id: 'php-site',
    name: 'PHP site',
    runtime: TemplateRuntime.php,
    description: 'Single-file PHP page with a form and a shared stylesheet.',
    files: {
      'index.php': r'''<?php
$name = trim($_GET['name'] ?? '');
?>
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>PHP on Praxis</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <main>
      <p class="eyebrow">PRAXIS · PHP</p>
      <h1><?= $name === '' ? 'Hello from PHP.' : 'Hello, ' . htmlspecialchars($name) . '.' ?></h1>
      <form method="get">
        <input name="name" placeholder="Your name" value="<?= htmlspecialchars($name) ?>" />
        <button type="submit">Say hello</button>
      </form>
      <p class="meta">PHP <?= PHP_VERSION ?></p>
    </main>
  </body>
</html>
''',
      'style.css':
          '''body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0f1210; color: #eef3ee; font-family: system-ui, sans-serif; }
main { width: min(88vw, 460px); }
.eyebrow { color: #7c9a86; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: clamp(30px, 8vw, 46px); line-height: 1.05; }
form { display: flex; gap: 8px; margin: 22px 0; }
input { flex: 1; padding: 11px 12px; border-radius: 8px; border: 1px solid #2b332d; background: #151a16; color: inherit; }
button { padding: 11px 16px; border-radius: 8px; border: 0; background: #7c9a86; color: #0f1210; font-weight: 700; }
.meta { color: #7c9a86; font-size: 12px; }
''',
      'README.md': '''# PHP on Praxis

```sh
php -S 0.0.0.0:8080
```

Open the preview and set the port to 8080.
''',
    },
  ),
  ProjectTemplate(
    id: 'php-api',
    name: 'PHP JSON API',
    runtime: TemplateRuntime.php,
    description: 'A small JSON endpoint with routing and error handling.',
    files: {
      'index.php': r'''<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?? '/';

if ($path === '/api/health') {
    echo json_encode(['ok' => true, 'time' => date(DATE_ATOM)]);
    exit;
}

if ($path === '/' || $path === '/api') {
    echo json_encode([
        'name' => 'Praxis PHP API',
        'routes' => ['/api/health'],
    ], JSON_PRETTY_PRINT);
    exit;
}

http_response_code(404);
echo json_encode(['error' => 'Not found', 'path' => $path]);
''',
      'README.md': '''# PHP JSON API on Praxis

```sh
php -S 0.0.0.0:8080 index.php
```

`GET /api/health` returns a JSON status object.
''',
    },
  ),
  ProjectTemplate(
    id: 'go-http',
    name: 'Go HTTP server',
    runtime: TemplateRuntime.go,
    description: 'net/http server with a JSON health route and logging.',
    files: {
      'go.mod': 'module hello-praxis\n\ngo 1.22\n',
      'main.go': '''package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"ok":   true,
			"time": time.Now().Format(time.RFC3339),
		})
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write([]byte("<h1>Hello from Go</h1><p>Edit main.go to begin.</p>"))
	})

	log.Printf("listening on http://localhost:%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
''',
      'README.md': '''# Go on Praxis

```sh
go run .
```

The server listens on port 8080 and logs the address on start.
''',
    },
  ),
  ProjectTemplate(
    id: 'go-cli',
    name: 'Go CLI',
    runtime: TemplateRuntime.go,
    description: 'Command-line starter with flags and a small test.',
    files: {
      'go.mod': 'module hello-cli\n\ngo 1.22\n',
      'main.go': '''package main

import (
	"flag"
	"fmt"
)

func greet(name string, shout bool) string {
	message := fmt.Sprintf("Hello, %s", name)
	if shout {
		message += "!"
	}
	return message
}

func main() {
	name := flag.String("name", "Praxis", "who to greet")
	shout := flag.Bool("shout", false, "add an exclamation mark")
	flag.Parse()
	fmt.Println(greet(*name, *shout))
}
''',
      'main_test.go': '''package main

import "testing"

func TestGreet(t *testing.T) {
	if got := greet("Praxis", true); got != "Hello, Praxis!" {
		t.Fatalf("unexpected greeting: %s", got)
	}
}
''',
      'README.md': '''# Go CLI on Praxis

```sh
go run . --name Praxis --shout
go test ./...
```
''',
    },
  ),
];
