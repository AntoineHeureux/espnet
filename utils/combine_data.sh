#!/usr/bin/env bash
# combine_data.sh : fusionne plusieurs répertoires de données au format Kaldi
# (remplacement léger de utils/combine_data.sh de Kaldi).
#
# Usage : combine_data.sh [--extra-files "f1 f2"] [--skip-fix true|false] <dest> <src1> [<src2> ...]
#
# - utt2spk et wav.scp sont obligatoires dans chaque source ;
# - text, segments, utt2dur, utt2num_frames, reco2dur, utt2uniq, feats.scp et les
#   --extra-files sont fusionnés s'ils existent dans TOUTES les sources ;
#   segments et text présents dans une partie seulement des sources => erreur
#   (une source avec segments et une sans ne peuvent pas être mélangées) ;
# - sortie triée (LC_ALL=C), clés dupliquées refusées, spk2utt régénéré ;
# - --skip-fix est accepté pour compatibilité avec Kaldi ; le tri est toujours fait ;
# - le résultat est ensuite contrôlé avec validate_data_dir.sh s'il est à côté de ce script.

set -eu
export LC_ALL=C

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
die()   { echo "combine_data.sh: ERREUR : $*" >&2; exit 1; }
warn()  { echo "combine_data.sh: AVERTISSEMENT : $*" >&2; }

extra_files=""
while [ $# -gt 0 ]; do
  case "$1" in
    --extra-files) [ $# -ge 2 ] || usage; extra_files=$2; shift 2 ;;
    --skip-fix)    [ $# -ge 2 ] || usage; shift 2 ;;
    -h|--help)     usage ;;
    --)            shift; break ;;
    --*)           die "option inconnue : $1" ;;
    *)             break ;;
  esac
done
[ $# -ge 2 ] || usage
dest=$1; shift
srcs=("$@")

dest_real=$(readlink -f "$dest")
for s in "${srcs[@]}"; do
  [ -d "$s" ] || die "répertoire source introuvable : $s"
  [ "$(readlink -f "$s")" != "$dest_real" ] || die "la destination ne peut pas être une des sources ($s)"
  for f in utt2spk wav.scp; do
    [ -s "$s/$f" ] || die "$s/$f est absent ou vide"
  done
done

mkdir -p "$dest"
optional="text segments utt2dur utt2num_frames reco2dur utt2uniq feats.scp $extra_files"
for f in utt2spk spk2utt wav.scp $optional; do rm -f "$dest/$f"; done

# fichiers obligatoires
for f in utt2spk wav.scp; do
  files=()
  for s in "${srcs[@]}"; do files+=("$s/$f"); done
  cat "${files[@]}" | sort -u > "$dest/$f"
done

# fichiers optionnels : tout ou rien
for f in $optional; do
  files=()
  for s in "${srcs[@]}"; do
    if [ -s "$s/$f" ]; then files+=("$s/$f"); fi
  done
  n=${#files[@]}
  if [ "$n" -eq "${#srcs[@]}" ]; then
    cat "${files[@]}" | sort -u > "$dest/$f"
  elif [ "$n" -gt 0 ]; then
    case "$f" in
      segments|text)
        die "$f existe dans $n source(s) sur ${#srcs[@]} : impossible de les mélanger. Pour 'segments', génère aussi un segments pour les sources qui n'en ont pas (data_augmentation.py le fait quand son entrée en a un)." ;;
      *) warn "$f présent dans seulement $n source(s) sur ${#srcs[@]} : ignoré" ;;
    esac
  fi
done

# clés dupliquées = identifiants en conflit entre sources
for f in utt2spk wav.scp text segments; do
  [ -f "$dest/$f" ] || continue
  d=$(awk '{print $1}' "$dest/$f" | uniq -d | head -3 | tr '\n' ' ')
  [ -z "$d" ] || die "clés dupliquées dans $dest/$f : $d (identifiants en conflit entre sources ? ajoute un préfixe)"
done

awk '{u[$2]=u[$2]" "$1} END{for (s in u) print s u[s]}' "$dest/utt2spk" | sort > "$dest/spk2utt"

echo "combine_data.sh: $(wc -l < "$dest/utt2spk") énoncés, $(wc -l < "$dest/spk2utt") locuteurs combinés dans $dest"

validator="$(dirname "$(readlink -f "$0")")/validate_data_dir.sh"
if [ -f "$validator" ]; then
  bash "$validator" --no-feats --non-print "$dest"
fi