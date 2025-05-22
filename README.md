# Kubernetes Supabase Test

Projet de test et d'exploration pour déployer une stack Supabase sur Kubernetes (k3d) sans Docker Compose, avec une gestion GitOps via Argo CD.

---

## 🎯 Objectifs

- Déployer Supabase (Postgres, Studio, Kong, Realtime, etc.) dans un cluster Kubernetes (k3d).
- Remplacer Docker Compose par une architecture Kubernetes native.
- Utiliser Argo CD pour la gestion GitOps.
- Ajouter progressivement des composants (auth, stockage, fonctions, etc.).

---

## 📦 Stack technique

- Kubernetes via **k3d**
- Supabase (via images officielles Docker Hub)
- Argo CD
- Kustomize
- (Optionnel) Helm

---

## 🗂️ Structure du projet

\`\`\`bash
kubernetes-supabase-test/
├── apps/                   # Manifests pour chaque service Supabase
│   ├── postgres/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── studio/
│   ├── kong/
│   ├── auth/
│   ├── realtime/
│   ├── rest/
│   ├── storage/
│   └── ...
├── overlays/               # Configs spécifiques à un environnement
│   └── dev/
│       └── kustomization.yaml
├── argo-cd/                # Définition de l'application Argo CD
│   └── supabase-app.yaml
├── scripts/                # Scripts d'initialisation et d'automatisation
│   └── init-secrets.sh
├── secrets/                # Secrets non versionnés
│   └── README.md
├── .gitignore
└── README.md
\`\`\`

---

## 🚀 Démarrage avec k3d

### 1. Prérequis

- [k3d](https://k3d.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kubectl.docs.kubernetes.io/)
- [argocd CLI](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- (Optionnel) [helm](https://helm.sh/)

### 2. Création du cluster k3d

\`\`\`bash
k3d cluster create supabase-cluster --agents 2 --port "8080:80@loadbalancer"
\`\`\`

### 3. Déploiement avec kustomize

\`\`\`bash
kubectl apply -k overlays/dev/
\`\`\`

### 4. Ajouter le projet à Argo CD

\`\`\`bash
argocd app create supabase   --repo https://github.com/PierreOudin/kubernetes-supabase-test.git   --path overlays/dev   --dest-server https://kubernetes.default.svc   --dest-namespace default   --sync-policy automated
\`\`\`

---

## 🧪 Priorité de mise en place

1. ✅ postgres
2. ✅ studio
3. ✅ kong
4. ✅ rest
5. ✅ realtime
6. ✅ auth
7. 📁 storage
8. 🧪 functions
9. ☁️ imgproxy

---

## 🔐 Gestion des secrets

- Secrets placés dans `secrets/` (non versionnés).
- Prévoir intégration de :
  - Sealed Secrets (Bitnami)
  - External Secrets Operator
  - SOPS

---

## 📌 TODO

- [x] Initialisation du repo avec structure Kubernetes
- [ ] Déploiement de postgres avec supabase/postgres
- [ ] Déploiement progressif des composants
- [ ] Configuration Argo CD + auto-sync
- [ ] Intégration d'un gestionnaire de secrets
- [ ] CI/CD (GitHub Actions)

---

## 🔗 Liens utiles

- [Supabase GitHub](https://github.com/supabase/supabase)
- [Argo CD](https://argo-cd.readthedocs.io/)
- [Kustomize](https://kubectl.docs.kubernetes.io/)
- [Helm](https://helm.sh/)
