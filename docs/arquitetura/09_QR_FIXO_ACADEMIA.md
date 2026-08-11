# QR fixo da academia para presença

**Status:** implementado no código em 2026-08-11; exige deploy das Functions e
das Rules junto de uma versão do app que reconheça o payload v2.

Ordem segura de rollout: publicar primeiro as três Functions e as Rules; validar
uma leitura em ambiente de teste; somente então distribuir a versão do app.

## Objetivo

Permitir que o proprietário imprima uma única placa de QR Code. O mesmo código
serve para turmas existentes e futuras. Depois da leitura, o aluno escolhe uma
turma disponível e recebe a presença naquela turma e no dia da leitura.

## Decisão arquitetural

O QR permanente não contém `classId`, data, horário, matrícula ou permissão. O
payload público contém apenas:

```json
{"v":2,"k":"academy_checkin","a":"<academyId>","c":"<opaqueCode>"}
```

O código é criado uma única vez pela callable `getOrCreateFixedAcademyQr` e
persistido em `academies/{academyId}.fixedAttendanceQr`. Chamadas futuras
devolvem o mesmo valor. Criar ou editar turmas não toca nesse campo.

## Fluxo

1. Proprietário abre **Chamada por QR > QR fixo da academia**.
2. `getOrCreateFixedAcademyQr` confirma autenticação e papel de administrador.
3. A tela renderiza o QR e oferece impressão/PDF em A4.
4. O aluno lê o payload no scanner já existente.
5. `resolveFixedAcademyQr` deriva o `studentId` do vínculo autenticado e retorna
   somente turmas ativas, permitidas pela matrícula e dentro da janela atual.
6. O aluno escolhe a turma.
7. `checkInWithFixedAcademyQr` repete todas as validações dentro do comando e
   grava presença + contador em uma transação.

## Invariantes server-side

- usuário autenticado e vinculado à academia do QR;
- aluno existente e com status ativo;
- código igual ao valor permanente habilitado da academia;
- turma existente e ativa;
- turma aberta ou aluno presente em `studentIds`;
- schedule dentro de 30 minutos antes até 60 minutos após a aula;
- suporte a aulas que atravessam a meia-noite;
- id determinístico `{studentId}_{classId}_{YYYYMMDD}`;
- incremento de `attendanceCount` na mesma transação;
- campos derivados de turma, esporte, peso e nome são lidos no servidor;
- origem auditável `source: academy_fixed_qr`.

O cliente não escreve presença nem contador neste fluxo. O campo
`fixedAttendanceQr` também foi retirado das atualizações permitidas pelas Rules;
somente Admin SDK/Functions o altera.

## Segurança e limite consciente

Um QR impresso pode ser fotografado. Portanto, seu valor não é tratado como
segredo nem como prova suficiente de presença física. O risco é limitado por
autenticação, vínculo, matrícula, status, janela de horário e deduplicação.

Se for necessário comprovar proximidade física no futuro, a evolução correta é
adicionar App Check e um segundo sinal verificável (BLE beacon, Wi-Fi/catraca ou
geofence com política de privacidade). Rotacionar o QR contrariaria o requisito
de impressão e não deve ser usado como gambiarra para simular localização.

## Compatibilidade

- payload v1 rotativo por turma continua funcionando;
- payload v1 de musculação continua usando `selfCheckin`;
- payload v2 é reconhecido antes do fluxo rotativo;
- nenhuma turma atual precisa de migração;
- turmas futuras entram automaticamente quando ativas e com schedule elegível.

## Arquivos

- `functions/fixed_academy_qr.js`: regras, queries e comandos autoritativos;
- `lib/services/fixed_academy_qr_service.dart`: contrato e adapter callable;
- `lib/screens/admin/fixed_academy_qr_screen.dart`: visualização e impressão;
- `lib/screens/portal/widgets/fixed_qr_class_selection.dart`: escolha da turma;
- `lib/screens/portal/qr_scan_screen.dart`: orquestração do scanner;
- `functions/test/fixed_academy_qr.test.js`: domínio de horário/matrícula;
- `test/services/fixed_academy_qr_service_test.dart`: contrato Flutter.
