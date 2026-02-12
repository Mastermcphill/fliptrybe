# FlipTrybe Marketing Site

Static marketing site for FlipTrybe role flows and economics.

## Stack
- Next.js 14 (App Router)
- Tailwind CSS

## Local Run
```bash
npm install
npm run dev
```

## Build
```bash
npm run build
npm run start
```

## Deploy
### Vercel
1. Import `website/` as project root.
2. Set framework to Next.js.
3. Deploy.

### Netlify
1. Set base directory to `website`.
2. Build command: `npm run build`.
3. Publish directory: `.next` (or use Netlify Next.js plugin defaults).

## Environment Placeholders
Create `.env.local` from `.env.example`.

No secrets are required for static pages; placeholders exist for future API-driven sections.
