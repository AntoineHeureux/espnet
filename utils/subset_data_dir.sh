src=data/train_sp
dst=data/train_sp_small
list=/workspace/liste_test.txt

# 100 énoncés tirés au hasard, de façon reproductible
shuf -n 100 --random-source=<(yes) $src/utt2spk | cut -d' ' -f1 | sort > $list

rm -rf $dst; mkdir -p $dst

# fichiers indexés par énoncé
for f in text utt2spk segments utt2dur utt2num_frames; do
  [ -f $src/$f ] && awk 'NR==FNR{k[$1]=1; next} ($1 in k)' $list $src/$f > $dst/$f
done

# wav.scp : par enregistrement si segments existe, sinon par énoncé
if [ -f $dst/segments ]; then
  awk '{print $2}' $dst/segments | sort -u > $dst/.recs
  awk 'NR==FNR{k[$1]=1; next} ($1 in k)' $dst/.recs $src/wav.scp > $dst/wav.scp
  rm $dst/.recs
else
  awk 'NR==FNR{k[$1]=1; next} ($1 in k)' $list $src/wav.scp > $dst/wav.scp
fi

# spk2utt
awk '{a[$2]=a[$2]" "$1} END{for(s in a) print s a[s]}' $dst/utt2spk | sort > $dst/spk2utt

wc -l $dst/{text,utt2spk,wav.scp,spk2utt}