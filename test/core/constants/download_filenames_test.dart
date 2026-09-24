import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/download_filenames.dart';

void main() {
  group('DownloadFileNames.metadataCandidatesForAudio', () {
    test('單頁 audio.m4a 只配對共用的 metadata.json', () {
      expect(DownloadFileNames.metadataCandidatesForAudio('audio.m4a'), [
        'metadata.json',
      ]);
    });

    test('song.m4a 與 audio.m4a 同屬單頁，只配對 metadata.json', () {
      expect(DownloadFileNames.metadataCandidatesForAudio('song.m4a'), [
        'metadata.json',
      ]);
    });

    test('P01.m4a 先找分頁專屬檔，再退回共用檔（順序即優先序）', () {
      expect(DownloadFileNames.metadataCandidatesForAudio('P01.m4a'), [
        'metadata_P01.json',
        'metadata.json',
      ]);
    });

    test('P100.m4a 不截斷頁號，P100 完整保留', () {
      expect(DownloadFileNames.metadataCandidatesForAudio('P100.m4a'), [
        'metadata_P100.json',
        'metadata.json',
      ]);
    });

    test('P1.m4a 不做補零正規化：配對 metadata_P1.json，不是 metadata_P01.json', () {
      // 寫入端只產生補零的 `P{NN}.m4a`，所以磁碟上不會有 `P1.m4a`。這裡刻意
      // 不猜測補零：寧可配不到而退回共用檔，也不去猜一個可能不存在的檔名。
      expect(DownloadFileNames.metadataCandidatesForAudio('P1.m4a'), [
        'metadata_P1.json',
        'metadata.json',
      ]);
    });

    test('舊版布局 P01 - 標題.m4a 只配對共用 metadata.json（不拆頁號）', () {
      // 舊版檔名把頁號與標題黏在一起，拆出來的 `metadata_P01 - 標題.json`
      // 永遠不存在；而舊版布局的 metadata 本來就是共用的。
      expect(DownloadFileNames.metadataCandidatesForAudio('P01 - 標題.m4a'), [
        'metadata.json',
      ]);
    });

    test('帶目錄的輸入只看 basename：foo/bar/P02.m4a', () {
      expect(DownloadFileNames.metadataCandidatesForAudio('foo/bar/P02.m4a'), [
        'metadata_P02.json',
        'metadata.json',
      ]);
    });

    test('帶目錄的單頁輸入同樣只看 basename：foo/bar/audio.m4a', () {
      expect(
        DownloadFileNames.metadataCandidatesForAudio('foo/bar/audio.m4a'),
        ['metadata.json'],
      );
    });

    test('副檔名大小寫不影響配對結果（P01.M4A 等同 P01.m4a）', () {
      // 這是 basenameWithoutExtension 的性質，不是掃描器的：scanner 用
      // `endsWith('.m4a')` 篩選，`.M4A` 對它仍不可見（已記錄的既有不一致）。
      expect(DownloadFileNames.metadataCandidatesForAudio('P01.M4A'), [
        'metadata_P01.json',
        'metadata.json',
      ]);
    });
  });
}
