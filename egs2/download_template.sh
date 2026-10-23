# 1. Se placer dans le dossier cible
cd /workspace/espnet/egs2

# 2. Initialiser le dépôt local
git init
git remote add origin https://github.com/espnet/espnet.git

# 3. Activer le sparse-checkout pour cibler uniquement TEMPLATE
git config core.sparseCheckout true
echo "egs2/TEMPLATE" >> .git/info/sparse-checkout

# 4. Récupérer l'historique nécessaire
git fetch origin 28e2a975122e675f33e16f25dac84d2dba378afc

# 5. Se placer sur la version EXACTE de votre clone local
# (remplacez <VOTRE_HASH_COMMIT> par le hash obtenu à l'étape 1)
git checkout 28e2a975122e675f33e16f25dac84d2dba378afc