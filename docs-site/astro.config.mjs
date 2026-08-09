// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { starlightBasePath } from 'starlight-base-path';

// https://astro.build/config
export default defineConfig({
	site: 'https://deekshith-poojary98.github.io',
	base: '/robot-studio',
	integrations: [
		starlight({
			title: 'Robot Studio',
			description:
				'User guide for Robot Studio — the desktop IDE for Robot Framework.',
			favicon: '/favicon.svg',
			head: [
				{
					tag: 'link',
					attrs: {
						rel: 'icon',
						href: '/favicon-32.png',
						type: 'image/png',
						sizes: '32x32',
					},
				},
				{
					tag: 'link',
					attrs: {
						rel: 'icon',
						href: '/favicon-192.png',
						type: 'image/png',
						sizes: '192x192',
					},
				},
				{
					tag: 'link',
					attrs: {
						rel: 'apple-touch-icon',
						href: '/apple-touch-icon.png',
						sizes: '180x180',
					},
				},
			],
			logo: {
				light: './src/assets/logo-light.png',
				dark: './src/assets/logo-dark.png',
				replacesTitle: true,
				alt: 'Robot Studio',
			},
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/deekshith-poojary98/robot-studio',
				},
			],
			editLink: {
				baseUrl:
					'https://github.com/deekshith-poojary98/robot-studio/edit/main/docs-site/',
			},
			customCss: ['./src/styles/custom.css'],
			plugins: [starlightBasePath()],
			components: {
				Hero: './src/components/overrides/Hero.astro',
			},
			sidebar: [
				{
					label: 'Get started',
					items: [
						{ label: 'What is Robot Studio?', slug: 'getting-started/overview' },
						{ label: 'Install', slug: 'getting-started/install' },
						{ label: 'Your first project', slug: 'getting-started/first-project' },
						{ label: 'Run your first tests', slug: 'getting-started/first-run' },
					],
				},
				{
					label: 'Everyday workflows',
					items: [
						{ label: 'Write and edit tests', slug: 'workflows/writing-tests' },
						{ label: 'Environments & packages', slug: 'workflows/environments' },
						{ label: 'Run, stop & re-run', slug: 'workflows/running-tests' },
						{ label: 'Find code & symbols', slug: 'workflows/search' },
						{ label: 'Git source control', slug: 'workflows/git' },
						{ label: 'Reports & failed tests', slug: 'workflows/reports' },
					],
				},
				{
					label: 'Features',
					items: [
						{ label: 'Editor & language intelligence', slug: 'features/editor' },
						{ label: 'Test Explorer', slug: 'features/test-explorer' },
						{ label: 'Insights', slug: 'features/insights' },
						{ label: 'Robot Doctor', slug: 'features/robot-doctor' },
						{ label: 'Terminal', slug: 'features/terminal' },
						{ label: 'Command palette', slug: 'features/command-palette' },
					],
				},
				{
					label: 'Tips',
					items: [
						{ label: 'Keyboard shortcuts', slug: 'tips/keyboard-shortcuts' },
					],
				},
				{
					label: 'Help',
					items: [
						{ label: 'Troubleshooting', slug: 'troubleshooting/common-issues' },
						{ label: 'Glossary', slug: 'reference/glossary' },
						{ label: 'Settings reference', slug: 'reference/settings' },
					],
				},
			],
		}),
	],
});
