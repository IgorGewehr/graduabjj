# Guia de Integração - Galeria de Fotos de Competições

## ✅ O que já foi criado

### Modelos e Serviços
- ✅ `lib/models/competition_photo.dart` - Modelo de dados
- ✅ `lib/services/competition_photo_service.dart` - Serviço com todos os métodos

### Widgets
- ✅ `lib/widgets/competitions/photo_card.dart` - Card de foto individual
- ✅ `lib/widgets/competitions/photo_upload_sheet.dart` - Bottom sheet para upload
- ✅ `lib/widgets/competitions/competition_gallery.dart` - Widget principal da galeria
- ✅ `lib/widgets/competitions/photo_fullscreen_viewer.dart` - Visualizador fullscreen

## 📝 Como Integrar nas Telas

### 1. Adicionar ao Competition Detail Screen (Admin)

Localize o arquivo da tela de detalhes da competição (provavelmente em `lib/screens/admin/` ou similar) e adicione:

```dart
import 'package:graduabjj/widgets/competitions/competition_gallery.dart';

// No widget da tela de detalhes, adicione uma nova tab:

TabBar(
  controller: _tabController,
  tabs: const [
    Tab(text: 'Detalhes'),
    Tab(text: 'Inscritos'),
    Tab(text: 'Resultados'),
    Tab(text: 'Galeria'), // NOVA TAB
  ],
),

// No TabBarView, adicione:

TabBarView(
  controller: _tabController,
  children: [
    // ... outras tabs ...

    // NOVA TAB - Galeria
    CompetitionGallery(
      academyId: academyId,
      competitionId: competition.id,
      competitionName: competition.name,
      studentId: currentUser.studentId, // ID do estudante se aplicável
      studentName: currentUser.studentName,
      isEnrolled: false, // Para admin, não precisa estar inscrito
      isAdmin: true, // Admin tem upload ilimitado
    ),
  ],
),
```

### 2. Adicionar ao Portal do Aluno

Localize o arquivo do portal de competições do aluno e adicione:

```dart
import 'package:graduabjj/widgets/competitions/competition_gallery.dart';

// Adicione uma nova tab "Minha Galeria"

TabBar(
  tabs: const [
    Tab(text: 'Próximas'),
    Tab(text: 'Minhas Inscrições'),
    Tab(text: 'Histórico'),
    Tab(text: 'Minha Galeria'), // NOVA TAB
  ],
),

// No corpo da tab:

// Opção 1: Mostrar galeria de uma competição específica
CompetitionGallery(
  academyId: academyId,
  competitionId: selectedCompetition.id,
  competitionName: selectedCompetition.name,
  studentId: currentStudentId,
  studentName: currentStudentName,
  isEnrolled: true,
  isAdmin: false,
),

// Opção 2: Mostrar todas as fotos do aluno (ListView com múltiplas galerias)
ListView.builder(
  itemCount: enrolledCompetitions.length,
  itemBuilder: (context, index) {
    final competition = enrolledCompetitions[index];
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              competition.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          CompetitionGallery(
            academyId: academyId,
            competitionId: competition.id,
            competitionName: competition.name,
            studentId: currentStudentId,
            studentName: currentStudentName,
            isEnrolled: true,
            isAdmin: false,
          ),
        ],
      ),
    );
  },
),
```

### 3. Adicionar Dependências (se ainda não tiver)

Verifique se estas dependências estão no `pubspec.yaml`:

```yaml
dependencies:
  image_picker: ^1.0.0  # Para selecionar fotos
  intl: ^0.18.0         # Para formatação de datas
```

Se não estiver, adicione e rode:

```bash
flutter pub get
```

### 4. Configurar Permissões

#### iOS (ios/Runner/Info.plist)

Adicione se ainda não tiver:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Precisamos de acesso à sua galeria para você adicionar fotos das competições</string>
<key>NSCameraUsageDescription</key>
<string>Precisamos de acesso à câmera para você tirar fotos das competições</string>
```

#### Android (android/app/src/main/AndroidManifest.xml)

As permissões já devem estar configuradas se você usa image_picker. Verifique:

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.CAMERA"/>
```

## 🎨 Customizações Opcionais

### Personalizar Cores

Você pode customizar as cores dos widgets editando os arquivos criados. Por exemplo, em `photo_card.dart`:

```dart
// Mudar cores das medalhas
Color _getMedalColor() {
  switch (photo.medalType) {
    case CompetitionPosition.gold:
      return const Color(0xFFFFD700); // Altere aqui
    // ...
  }
}
```

### Adicionar Loading States

Os widgets já têm loading states básicos, mas você pode melhorar:

```dart
// Em competition_gallery.dart
if (_isLoading) {
  return const Center(
    child: CircularProgressIndicator(),
  );
}
```

## 🐛 Troubleshooting

### Erro: "Cannot access uninitialized variable"

- Verifique se todas as variáveis obrigatórias estão sendo passadas para os widgets
- Certifique-se de que `academyId`, `competitionId`, etc. estão disponíveis no escopo

### Erro: "Image picker not found"

- Execute `flutter pub get`
- No iOS, pode precisar rodar `cd ios && pod install`

### Fotos não aparecem

- Verifique as regras de segurança do Firestore e Storage no console Firebase
- Confirme que o usuário tem permissão para acessar a academia
- Verifique se as fotos existem no Firebase Storage

### Upload falha

- Verifique o tamanho da imagem (máx 10MB)
- Confirme que o usuário está inscrito na competição
- Verifique se o limite de 3 fotos não foi atingido (para alunos)

## ✅ Checklist de Integração

- [ ] Dependências adicionadas ao `pubspec.yaml`
- [ ] Permissões configuradas (iOS e Android)
- [ ] Galeria adicionada na tela de detalhes da competição (admin)
- [ ] Galeria adicionada no portal do aluno
- [ ] Testado upload de foto
- [ ] Testado visualização de fotos
- [ ] Testado delete de foto (própria e de outros)
- [ ] Testado limite de 3 fotos para alunos
- [ ] Testado upload ilimitado para admins
- [ ] Testado lightbox/fullscreen
- [ ] Testado sincronização com Next.js

## 📱 Exemplo Completo de Integração

```dart
// Exemplo de como usar o widget completo em uma tela

import 'package:flutter/material.dart';
import 'package:graduabjj/widgets/competitions/competition_gallery.dart';

class CompetitionDetailScreen extends StatelessWidget {
  final String academyId;
  final Competition competition;
  final String? currentStudentId;
  final String? currentStudentName;
  final bool isAdmin;
  final bool isEnrolled;

  const CompetitionDetailScreen({
    super.key,
    required this.academyId,
    required this.competition,
    this.currentStudentId,
    this.currentStudentName,
    required this.isAdmin,
    required this.isEnrolled,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(competition.name),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.info), text: 'Detalhes'),
              Tab(icon: Icon(Icons.people), text: 'Inscritos'),
              Tab(icon: Icon(Icons.emoji_events), text: 'Resultados'),
              Tab(icon: Icon(Icons.photo_library), text: 'Galeria'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Detalhes tab
            const Center(child: Text('Detalhes')),

            // Inscritos tab
            const Center(child: Text('Inscritos')),

            // Resultados tab
            const Center(child: Text('Resultados')),

            // Galeria tab
            CompetitionGallery(
              academyId: academyId,
              competitionId: competition.id,
              competitionName: competition.name,
              studentId: currentStudentId,
              studentName: currentStudentName,
              isEnrolled: isEnrolled,
              isAdmin: isAdmin,
            ),
          ],
        ),
      ),
    );
  }
}
```

## 🚀 Próximos Passos

1. Integre os widgets nas telas conforme os exemplos acima
2. Teste a funcionalidade completa
3. Faça upload de fotos de teste
4. Verifique a sincronização entre Flutter e Next.js
5. Deploy para produção quando estiver tudo funcionando!
