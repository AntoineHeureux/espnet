#!/usr/bin/env bash
# validate_data_dir.sh : contrôle simplifié d'un répertoire de données au format Kaldi
# (remplacement léger de utils/validate_data_dir.sh de Kaldi, suffisant pour ESPnet).
#
# Usage : validate_data_dir.sh [options] <data-dir>
#   --no-feats      ne pas contrôler feats.scp (accepté ; ESPnet n'en a pas)
#   --no-text       ne pas exiger ni contrôler le fichier text
#   --no-wav        ne pas exiger ni contrôler wav.scp / segments
#   --non-print     accepté pour compatibilité (l'UTF-8 est toujours accepté)
#   --no-spk-sort   ne pas vérifier que utt2spk est trié aussi par locuteur
#   --strict        l'ordre par locuteur devient une erreur (simple avertissement sinon)
#
# Contrôles : fichiers présents et bien formés, clés triées (LC_ALL=C) et uniques,
# mêmes énoncés dans utt2spk / text / segments (ou wav.scp), enregistrements de
# segments présents dans wav.scp, bornes de segments valides, spk2utt cohérent avec
# utt2spk, transcriptions non vides, pas de caractères de contrôle (dont \r Windows).
# Code retour : 0 si aucune erreur, 1 sinon.

set -u
export LC_ALL=C

no_feats=false; no_text=false; no_wav=false; no_spk_sort=false; strict=false
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --no-feats) no_feats=true; shift ;;
    --no-text) no_text=true; shift ;;
    --no-wav) no_wav=true; shift ;;
    --non-print) shift ;;
    --no-spk-sort) no_spk_sort=true; shift ;;
    --strict) strict=true; shift ;;
    -h|--help) usage ;;
    --*) echo "validate_data_dir.sh: option inconnue : $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || usage
data=${1%/}
[ -d "$data" ] || { echo "validate_data_dir.sh: répertoire introuvable : $data" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
errors=0; warnings=0
err()  { echo "validate_data_dir.sh: ERREUR : $*" >&2; errors=$((errors + 1)); }
warn() { echo "validate_data_dir.sh: AVERTISSEMENT : $*" >&2; warnings=$((warnings + 1)); }

# check_file <nom> <nb min de champs> <nb max de champs, 0 = illimité>
# Vérifie existence, format, tri et unicité des clés ; écrit la liste des clés dans $tmp/<nom>.keys
check_file() {
  local f="$data/$1" mn=$2 mx=$3 res d
  if [ ! -s "$f" ]; then err "$1 est absent ou vide"; return 1; fi
  res=$(awk -v mn="$mn" -v mx="$mx" \
    'NF<mn || (mx>0 && NF>mx) {c++; if (!l) l=NR} END{if (c) printf "%d ligne(s) mal formée(s), la première : ligne %d", c, l}' "$f")
  [ -z "$res" ] || err "$1 : $res"
  awk '{print $1}' "$f" | sort -c 2>/dev/null || err "$1 n'est pas trié par clé (le trier avec LC_ALL=C sort)"
  d=$(awk '{print $1}' "$f" | uniq -d | head -3 | tr '\n' ' ')
  [ -z "$d" ] || err "$1 : clés dupliquées, par exemple : $d"
  awk '{print $1}' "$f" | sort -u > "$tmp/$1.keys"
  return 0
}

# only_in <A> <B> : clés de A absentes de B (stocke le nombre dans $n et des exemples dans $ex)
only_in() {
  n=$(comm -23 "$tmp/$1.keys" "$tmp/$2.keys" | wc -l)
  ex=$(comm -23 "$tmp/$1.keys" "$tmp/$2.keys" | head -3 | tr '\n' ' ')
}

have_utt2spk=false
check_file utt2spk 2 2 && have_utt2spk=true

if $have_utt2spk; then
  # --- text
  if ! $no_text; then
    if check_file text 1 0; then
      only_in utt2spk text; [ "$n" -eq 0 ] || err "$n énoncé(s) de utt2spk absents de text, ex. : $ex"
      only_in text utt2spk; [ "$n" -eq 0 ] || err "$n énoncé(s) de text absents de utt2spk, ex. : $ex"
      empty=$(awk 'NF<2 {c++} END{print c+0}' "$data/text")
      [ "$empty" -eq 0 ] || err "text : $empty énoncé(s) sans transcription"
      ctrl=$(grep -c -P '[\x00-\x08\x0b-\x1f\x7f]' "$data/text" 2>/dev/null)
      [ "${ctrl:-0}" -eq 0 ] || err "text : ${ctrl} ligne(s) avec caractères de contrôle (fins de ligne Windows \\r ?)"
    fi
  fi

  # --- wav.scp / segments
  if ! $no_wav; then
    if check_file wav.scp 2 0; then
      if [ -f "$data/segments" ]; then
        if check_file segments 4 4; then
          only_in utt2spk segments; [ "$n" -eq 0 ] || err "$n énoncé(s) de utt2spk absents de segments, ex. : $ex"
          only_in segments utt2spk; [ "$n" -eq 0 ] || err "$n énoncé(s) de segments absents de utt2spk, ex. : $ex"
          awk '{print $2}' "$data/segments" | sort -u > "$tmp/recs.keys"
          n=$(comm -23 "$tmp/recs.keys" "$tmp/wav.scp.keys" | wc -l)
          ex=$(comm -23 "$tmp/recs.keys" "$tmp/wav.scp.keys" | head -3 | tr '\n' ' ')
          [ "$n" -eq 0 ] || err "$n enregistrement(s) de segments absents de wav.scp, ex. : $ex"
          n=$(comm -13 "$tmp/recs.keys" "$tmp/wav.scp.keys" | wc -l)
          [ "$n" -eq 0 ] || warn "$n enregistrement(s) de wav.scp non utilisés par segments"
          bad=$(awk '
            $3 !~ /^[0-9]+(\.[0-9]+)?$/ || ($4 != "-1" && $4 !~ /^[0-9]+(\.[0-9]+)?$/) {c++; if (!l) l=NR; next}
            ($4 != "-1" && $4+0 <= $3+0) {c++; if (!l) l=NR}
            END{if (c) printf "%d segment(s) invalide(s) (début/fin non numériques ou fin <= début), le premier : ligne %d", c, l}' "$data/segments")
          [ -z "$bad" ] || err "segments : $bad"
        fi
      else
        only_in utt2spk wav.scp; [ "$n" -eq 0 ] || err "$n énoncé(s) de utt2spk sans entrée dans wav.scp, ex. : $ex"
        only_in wav.scp utt2spk; [ "$n" -eq 0 ] || warn "$n entrée(s) de wav.scp absentes de utt2spk"
      fi
    fi
  fi

  # --- spk2utt cohérent avec utt2spk
  if check_file spk2utt 2 0; then
    awk '{u[$2]=u[$2]" "$1} END{for (s in u) print s u[s]}' "$data/utt2spk" | sort > "$tmp/spk2utt.expected"
    sort "$data/spk2utt" | cmp -s - "$tmp/spk2utt.expected" \
      || err "spk2utt incohérent avec utt2spk (le régénérer : awk '{u[\$2]=u[\$2]\" \"\$1} END{for(s in u) print s u[s]}' utt2spk | LC_ALL=C sort > spk2utt)"
  else
    :
  fi

  # --- utt2dur / feats.scp optionnels
  if [ -f "$data/utt2dur" ]; then
    if check_file utt2dur 2 2; then
      only_in utt2spk utt2dur; [ "$n" -eq 0 ] || warn "$n énoncé(s) sans durée dans utt2dur, ex. : $ex"
    fi
  fi
  if ! $no_feats && [ -f "$data/feats.scp" ]; then
    if check_file feats.scp 2 0; then
      only_in utt2spk feats.scp; [ "$n" -eq 0 ] || err "$n énoncé(s) de utt2spk absents de feats.scp, ex. : $ex"
    fi
  fi

  # --- utt2spk trié aussi par locuteur (exigé par les outils Kaldi, pas par ESPnet)
  if ! $no_spk_sort; then
    if ! sort -s -k2,2 "$data/utt2spk" | cmp -s - "$data/utt2spk"; then
      msg="utt2spk n'est pas trié par locuteur : des identifiants d'énoncés n'ont pas l'id du locuteur en préfixe (sans effet pour ESPnet)"
      if $strict; then err "$msg"; else warn "$msg"; fi
    fi
  fi
fi

if [ "$errors" -gt 0 ]; then
  echo "validate_data_dir.sh: $errors erreur(s), $warnings avertissement(s) dans $data" >&2
  exit 1
fi
n_utt=$(wc -l < "$data/utt2spk"); n_spk=$(wc -l < "$data/spk2utt" 2>/dev/null || echo 0)
echo "validate_data_dir.sh: Successfully validated data-directory $data ($n_utt énoncés, $n_spk locuteurs, $warnings avertissement(s))"