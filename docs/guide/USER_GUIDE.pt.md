# Guia do Usuário do HyperEdit

<p align="center"><a href="USER_GUIDE.md">English</a> · <a href="USER_GUIDE.ko.md">한국어</a> · <a href="USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="USER_GUIDE.ja.md">日本語</a> · <a href="USER_GUIDE.vi.md">Tiếng Việt</a> · <a href="USER_GUIDE.hi.md">हिन्दी</a> · <a href="USER_GUIDE.de.md">Deutsch</a> · <a href="USER_GUIDE.fr.md">Français</a> · <a href="USER_GUIDE.es.md">Español</a> · Português · <a href="USER_GUIDE.ar.md">العربية</a></p>

O HyperEdit é um editor de texto simples e rápido para macOS, construído em torno de um único arquivo grande de notas — daquele tipo ao qual você continua acrescentando coisas por anos. Este guia explica tudo o que você pode fazer com ele, na ordem em que provavelmente vai encontrar cada recurso. Os atalhos usam os símbolos do Mac: ⌘ Command, ⇧ Shift, ⌥ Option, ⌃ Control.

## Sumário

1. [Instalação e atualização](#1-instalação-e-atualização)
2. [Primeira execução](#2-primeira-execução)
3. [Idioma da interface](#3-idioma-da-interface)
4. [A janela](#4-a-janela)
5. [Noções básicas de edição](#5-noções-básicas-de-edição)
6. [Buscar e substituir](#6-buscar-e-substituir)
7. [Marcadores](#7-marcadores)
8. [Modo coluna e multicursor](#8-modo-coluna-e-multicursor)
9. [Ferramentas de linha e texto](#9-ferramentas-de-linha-e-texto)
10. [Snippets](#10-snippets)
11. [Macros](#11-macros)
12. [Recolhimento de código e marcas na barra de rolagem](#12-recolhimento-de-código-e-marcas-na-barra-de-rolagem)
13. [Editor dividido](#13-editor-dividido)
14. [Adição Rápida](#14-adição-rápida)
15. [Pré-visualização Markdown e cores de sintaxe](#15-pré-visualização-markdown-e-cores-de-sintaxe)
16. [Temas, fontes e texto CJK](#16-temas-fontes-e-texto-cjk)
17. [Salvamento, snapshots e codificações](#17-salvamento-snapshots-e-codificações)
18. [Referência de ajustes](#18-referência-de-ajustes)
19. [Atalhos de teclado](#19-atalhos-de-teclado)
20. [Arquivos que o HyperEdit grava](#20-arquivos-que-o-hyperedit-grava)
21. [Solução de problemas](#21-solução-de-problemas)
22. [Limitações conhecidas](#22-limitações-conhecidas)
23. [Blocos secretos e bloqueio do app](#23-blocos-secretos-e-bloqueio-do-app)
24. [Como obter ajuda](#24-como-obter-ajuda)

## 1. Instalação e atualização

**Requisitos:** macOS 15 (Sequoia) ou posterior. O app é um binário universal (Apple Silicon e Intel), assinado e autenticado pela Apple, então o Gatekeeper o abre sem avisos.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Para atualizar depois, use `brew upgrade --cask hyperedit`. O Homebrew 7 pode pedir que você confie no tap primeiro: `brew trust Hyeongcheol-An/tap`.

**DMG:** baixe `HyperEdit-x.y.z-universal.dmg` em [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), abra-o e arraste `HyperEdit.app` para a pasta `Applications` (Aplicativos). Para verificar um download, coloque `SHA256SUMS` ao lado do DMG e execute `shasum -a 256 -c SHA256SUMS`.

O HyperEdit não tem código de rede nem telemetria: ele nunca "liga para casa", e atualizar é algo que você faz, não algo que ele faz.

## 2. Primeira execução

O HyperEdit abre `~/Documents/HyperEdit/notes.md`. Se esse arquivo não existir, ele é criado com um breve texto de boas-vindas no seu idioma — apague o texto e comece a escrever. A ideia é que você mantenha um único arquivo e vá acrescentando a ele, mas nada obriga a isso:

- **⌘N** cria um novo arquivo de texto vazio (você escolhe o nome e a pasta).
- **⌘O** abre qualquer outro arquivo de texto. O último arquivo aberto é lembrado para a próxima execução.
- **Arquivo › Abrir Documento Padrão** leva você de volta ao `notes.md`.
- Arquivos binários (imagens, PDFs, arquivos compactados…) nunca são carregados no editor; eles abrem no app padrão.

A posição do cursor e da rolagem é lembrada por arquivo, então reabrir um arquivo de 30.000 linhas coloca você onde parou. **⌃⌘E** vai para o fim do documento — o lugar que você normalmente quer em um arquivo de notas.

## 3. Idioma da interface

A interface está disponível em onze idiomas: English (inglês), 한국어 (coreano), 简体中文 (chinês simplificado), 日本語 (japonês), Tiếng Việt (vietnamita), हिन्दी (híndi), Deutsch (alemão), Français (francês), Español (espanhol), Português (Brasil) e العربية (árabe). O texto em árabe é escrito da direita para a esquerda, mas o layout da janela — faixa de opções, barra lateral, painéis e editor — continua da esquerda para a direita, como na maioria dos editores de código; o texto que você digita segue a própria direção.

Por padrão, o HyperEdit segue o idioma do sistema. Para escolher outro:

1. Abra os **Ajustes (⌘,)** e veja a seção **Idioma** no topo.
2. Escolha um idioma no menu **Idioma da interface**. Cada idioma aparece na própria escrita, para que você encontre o seu mesmo que o idioma atual seja desconhecido. **Padrão do Sistema** mostra qual idioma o ajuste do sistema daria a você.
3. Clique em **Reiniciar Agora**. O documento é salvo primeiro, depois o HyperEdit encerra e reabre no novo idioma. (Você também pode continuar trabalhando e reiniciar mais tarde; a escolha já está salva.)

A escolha é guardada no mesmo lugar que **Ajustes do Sistema › Geral › Idioma e Região › Aplicativos**, então os dois sempre concordam. **Ajuda › Guia do Usuário** e o botão **Abrir Guia do Usuário** nos Ajustes abrem este guia no idioma atual da interface.

Um idioma que não está na lista recorre ao inglês (por exemplo, o chinês tradicional). O texto do documento, os nomes de arquivo e as datas que você insere não são afetados pelo idioma da interface — o dia da semana do carimbo de data/hora segue a localização do sistema.

## 4. A janela

O layout segue um editor clássico com faixa de opções (ribbon) e barra de título oculta.

- **Abas da faixa** — **Início** (Área de Transferência, Buscar, Inserir, Modo, Arquivo), **Editar** (Linhas, Maiúsculas/Minúsculas, Ordenar, Espaços, Coluna e Multicursor, Ferramentas, Macro), **Layout** (Tema, Painéis, Recolhimento, Markdown, Tamanho do Texto), **Avançado** (Ajustes, pasta de snapshots, recarregar, documento padrão), **Janela** (tela cheia, painéis). Quando a janela é estreita, os grupos se recolhem em ícones a partir da direita; a dica do ícone mostra o rótulo.
- **Barra de abas do documento** — o nome do arquivo atual com os botões Novo (⌘N) e Abrir (⌘O), além de acesso rápido a Salvar / Desfazer / Refazer.
- **Barra lateral (⌘1)** — **Arquivos** (a pasta do arquivo atual; um clique abre um arquivo), **Estrutura (⌘3)** (títulos, linhas `[Título]` e itens numerados, com uma caixa de filtro; o item atual fica destacado), **Linha do Tempo (⌘4)** (cabeçalhos de data/hora agrupados por mês, os mais recentes primeiro).
- **Painel inferior (⌘2)** — **Resultados da Busca**, **Marcadores** e **Saída**, um registro do que o app fez (salvamentos, substituições, erros).
- **Barra de status** — linha e coluna (mais o tamanho da seleção; passe o mouse para ver o deslocamento em caracteres), fim de linha (UNIX / DOS / MAC), codificação do arquivo, **COL** enquanto o modo coluna está ativado, número de cursores, número de linhas · tamanho do arquivo, a mensagem de status mais recente, a linguagem de sintaxe (esmaecida enquanto as cores de sintaxe estão desativadas), um menu de temas (marcado com "· Sistema" enquanto segue a aparência do sistema) e a porcentagem de zoom. A maioria dos itens é clicável.

## 5. Noções básicas de edição

- Digitar continua rápido em arquivos de vários megabytes; só a parte visível do documento é diagramada.
- **Quebra de linha** ⌥Z · **Números de linha** ⌥⌘L · **Zoom** ⌘= / ⌘- / ⌘0 (também na aba Layout).
- **Ir para a linha** ⌘L · **Fim do documento** ⌃⌘E.
- **Inserir Data/Hora** F7 insere um cabeçalho de data/hora como `## 2026-10-31 (sex) 14:05`. O dia da semana segue a localização do sistema. Linhas assim alimentam a Linha do Tempo.
- A linha atual é destacada e a coluna lateral mostra o número dela na cor do texto.
- Desfazer e refazer são ilimitados dentro de uma sessão, e cada ferramenta abaixo é um único passo de desfazer.

## 6. Buscar e substituir

- **Buscar (⌘F)** abre a barra de busca. Digite um termo e pressione Enter: cada ocorrência é listada no painel inferior com o número da linha, e as ocorrências ficam destacadas no editor enquanto a lista está aberta. Opções: expressão regular `.*`, diferenciar maiúsculas `Aa`, palavra inteira `W`. **F3 / ⇧F3** vão para a ocorrência seguinte / anterior. A lista se atualiza sozinha cerca de um segundo depois que você edita.
- **Substituir (⌘R)** adiciona um campo de substituição: substitua a ocorrência atual e siga para a próxima, ou use **Substituir Tudo**. Com expressão regular ativada, modelos como `$1` inserem grupos de captura. Substituir Tudo é um único passo de desfazer, mesmo com milhares de ocorrências.
- **Buscar em Arquivos (⇧⌘F)** busca em uma pasta (subpastas incluídas). Escolha a pasta, limite opcionalmente por máscaras como `*.md;*.txt` e clique em um resultado para abrir aquele arquivo naquela linha. Arquivos ocultos, pacotes, arquivos binários e arquivos com mais de 20 MB são ignorados.
- **Selecionar Todas as Ocorrências (⌥⌘A)** transforma cada ocorrência em um cursor — veja multicursor abaixo.

## 7. Marcadores

**⌘F2** marca a linha atual (ou remove o marcador), **F2 / ⌥F2** vão para o marcador seguinte / anterior, e a aba **Marcadores** do painel inferior lista todos eles; ali você pode dar um nome a cada marcador. Os marcadores acompanham suas linhas conforme você edita: inserir ou apagar linhas acima os move, apagar uma linha marcada o remove, e desfazer os traz de volta. Eles são guardados por documento em `~/Library/Application Support/HyperEdit/bookmarks/`, então nada é gravado ao lado dos seus arquivos.

## 8. Modo coluna e multicursor

- **Modo coluna (⌥C)** — segure ⌥ e arraste, ou use ⇧ com as setas, para selecionar um retângulo. Digitar e apagar passam a valer para todas as linhas do bloco, linhas curtas são completadas com espaço virtual, e copiar / colar funcionam linha a linha. A barra de status mostra **COL**. ⌥C de novo desativa o modo.
- **Inserir Número (⌥⌘N)** — preenche uma seleção em coluna (ou cada cursor) com uma sequência: escolha o valor inicial e o incremento; os números são preenchidos com zeros até a mesma largura.
- **Multicursor** — ⌘-clique adiciona um cursor, **⌘D** adiciona a próxima ocorrência do texto selecionado (ou da palavra no cursor), **⌥⌘A** seleciona todas as ocorrências da busca. Digitar vale para todos os cursores; Esc volta a um só. Cada edição com vários cursores é um único passo de desfazer.

## 9. Ferramentas de linha e texto

Elas ficam na aba **Editar** da faixa e no menu **Linha**. Atuam nas linhas selecionadas, ou na linha atual quando nada está selecionado.

| Grupo | Ferramentas |
|---|---|
| Linhas | Apagar Linha ⇧⌘K · Duplicar Linha ⇧⌘D · Mover Linha para Cima / Baixo ⌥↑ / ⌥↓ · Unir Linhas ⇧⌘J · Inverter Linhas · Numerar Linhas |
| Maiúsculas/Minúsculas | Maiúsculas · Minúsculas · Capitalizar · Inverter Caixa |
| Ordenar | Crescente · Decrescente · Ordem Numérica (pelo número no início de cada linha) · Remover Linhas Duplicadas |
| Espaços | Aparar Espaços Finais · Aparar Espaços no Início e no Fim · Remover Linhas Vazias · Tabs → Espaços · Espaços → Tabs |

- **Calcular (⌃⌘=)** avalia a seleção, ou a linha atual (a parte depois do último `=`, se houver), e acrescenta ` ⇒ resultado`: `3+0.5+0.25` vira `3+0.5+0.25 ⇒ 3.75`. Executar de novo em uma linha editada substitui o resultado antigo. Suportados: `+ - * / % ^`, parênteses, números como `1,234` e `1_000`, `sqrt abs round floor ceil min max`, `pi` e `e`. Uma expressão que não pode ser avaliada é relatada no painel Saída e o texto fica como está.
- **Alinhar Colunas (⌃⌘T)** preenche colunas separadas por tab (as linhas selecionadas, ou o bloco de linhas com tab ao redor do cursor) para que cada coluna comece na mesma coluna de exibição; caracteres coreanos, chineses e japoneses contam como duas células. Se todas as linhas contiverem `|`, o bloco é tratado como uma tabela Markdown: as células são preenchidas dentro de ` | `, as linhas `---` são redesenhadas e as colunas `--:` são alinhadas à direita.
- **Comentar (⌘/)** comenta ou descomenta as linhas com o marcador do tipo de arquivo: `//`, `#`, `--`… para código, `<!-- -->` para Markdown e HTML, `/* */` para CSS, `//` para notas simples. Se todas as linhas não vazias já estiverem comentadas, todas são descomentadas; caso contrário, todas são comentadas, com os marcadores alinhados na indentação mais rasa. Linhas vazias são ignoradas.
- **Formatar JSON (⌃⌘J) / Minificar JSON** formata (indentação de 2 espaços) ou compacta a seleção, ou o documento inteiro quando nada está selecionado. A ordem das chaves e o texto dos números são preservados, texto não ASCII fica sem escape, e a entrada pode conter comentários e vírgulas finais (JSONC). Em caso de erro de sintaxe, o texto fica como está, o painel Saída mostra `linha:coluna` e o cursor vai até lá.

## 10. Snippets

Digite uma palavra-gatilho e pressione **Tab** para expandi-la. Gatilhos integrados: `todo`, `date`, `time`, `now`, `meeting`, `table`, `link`, `code`. **Inserir Snippet… (⇧⌘I)** lista todos eles com uma caixa de filtro, e a aba Início tem um botão Snippet… para isso.

O corpo de um snippet pode conter variáveis — `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` — e paradas de tabulação `$1` … `$9`, `${1:placeholder}` e `$0`. Depois da expansão, Tab / ⇧Tab alternam entre as paradas (um número usado duas vezes vira um multicursor), e Esc ou um clique encerra a sessão.

**Editar Snippets…** (menu Editar ou aba Início) abre `~/Library/Application Support/HyperEdit/snippets.json` no próprio HyperEdit. Cada entrada tem um `trigger` (gatilho), um `name` e um `body`; o arquivo é relido depois que você o salva, então um novo gatilho funciona imediatamente.

## 11. Macros

Uma macro grava o que você digita e reproduz isso em outro lugar.

1. **Gravar Macro (⇧⌘M)** inicia a gravação; a barra de status mostra `● REC`. São gravados a digitação (para coreano e outros IMEs, os caracteres confirmados), o movimento do cursor, exclusões, novas linhas, colar, as ferramentas de texto e Buscar Seguinte (F3, com o termo buscado). Cliques do mouse, mudanças de seleção e edições com multicursor não são.
2. **⇧⌘M** de novo para a gravação.
3. **Reproduzir Macro (⌥⌘M)** reproduz a macro na posição do cursor. **Reproduzir Macro Várias Vezes…** repete até 10.000 vezes e para sozinho quando uma etapa de busca não encontra nada ou uma execução não altera nada — uma ferramenta prática do tipo "faça isso em todas as linhas". Uma execução inteira é um único passo de desfazer.

A última gravação fica só na memória até você encerrar o app, então nada sensível que você tenha digitado durante a gravação chega ao disco. **Salvar Última Macro Como…** a adiciona ao menu **Macro** de forma permanente; as macros salvas ficam em `~/Library/Application Support/HyperEdit/macros/macros.json`, que **Editar Arquivo de Macros…** abre no editor.

## 12. Recolhimento de código e marcas na barra de rolagem

**Recolher (⌥⌘←) / Expandir (⌥⌘→)** ocultam ou mostram a região no cursor; **⌥⇧⌘← / ⌥⇧⌘→** recolhem ou expandem tudo. Uma região é:

- as linhas indentadas sob a linha atual (linhas vazias são ignoradas),
- em Markdown, tudo o que está sob um título `#` até o próximo título do mesmo nível ou superior (blocos de código cercados também são recolhidos),
- em código, uma linha que termina em `{`, `[` ou `(` até a linha do fechamento correspondente.

Clique na seta na coluna lateral ou na pílula `⋯ N linhas` depois de uma linha recolhida para alternar com o mouse. Mover o cursor para dentro de uma linha recolhida (busca, ir para a linha, marcador, desfazer) a expande; ↑ / ↓ pulam as regiões recolhidas. As regiões recolhidas acompanham suas edições e duram até o fim da sessão.

**Marcas na barra de rolagem** — uma faixa fina na borda direita do editor mostra as ocorrências da busca (cor de destaque), os marcadores (cor de aviso), a linha do cursor e os cabeçalhos recolhidos em suas posições relativas no arquivo. Ela fica oculta quando o documento inteiro cabe na tela. Desative-a em **Visualizar › Marcas na Barra de Rolagem** ou no grupo Recolhimento da aba Layout (**Marcas Laterais**).

## 13. Editor dividido

**⌘\\** mostra o mesmo documento em dois editores, lado a lado; **Visualizar › Dividir › Dividir Empilhado** coloca um sobre o outro, e a aba Layout tem os mesmos botões. As duas visualizações editam o mesmo texto e compartilham um único histórico de desfazer — digite em uma, ⌘Z na outra — mas rolam de forma independente, então você pode ler uma parte do arquivo enquanto escreve em outra. Os comandos, a barra de status e a pré-visualização Markdown seguem o editor em que você clicou por último; **⌥⌘\\** move o foco para o outro. A barra de status mostra **SPLIT** enquanto a divisão está ativa; ⌘\\ de novo a fecha.

## 14. Adição Rápida

**Adição Rápida (⇧⌘N)** abre um pequeno painel flutuante para adicionar uma nota sem sair do que você estava fazendo. Digite a nota, pressione **⌘↩**, e ela é acrescentada ao fim do documento — com um cabeçalho de data/hora por padrão — salva na hora e desfeita em um único passo. O painel então se oculta e o foco volta ao app em que você estava. **Esc** fecha o painel e mantém o rascunho para a próxima vez.

Como o painel não ativa o HyperEdit, ele também funciona a partir de qualquer outro app por meio de um **atalho global**: **⌃⌥N** por padrão. Nos Ajustes você pode desativá-lo ou escolher ⌃⌥Space, ⌃⇧Space ou ⌃⌥⌘N, e desativar o cabeçalho de data/hora. O atalho usa o serviço de teclas de atalho do sistema, então nenhuma permissão de Acessibilidade é necessária. Se outro app já for dono da combinação, o painel Saída avisa na inicialização — escolha outra.

## 15. Pré-visualização Markdown e cores de sintaxe

- **Pré-visualização Markdown (⇧⌘P)** divide a janela com uma visualização renderizada do arquivo atual à direita: títulos, listas e listas de tarefas, tabelas, código cercado, citações, links e imagens, no estilo do tema atual. Ela acompanha a posição de rolagem do editor e é renderizada de novo pouco depois que você para de digitar. Os links abrem no seu navegador; HTML bruto no arquivo é mostrado como texto, nunca executado. Arquivos com mais de 2 MB mostram um aviso em vez da pré-visualização. A barra de status mostra **MD** enquanto ela está ativa.
- As **cores de sintaxe (⌃⌘H)** são escolhidas pela extensão do arquivo e mostradas na barra de status. Notas e Markdown recebem um conjunto leve de regras — URLs, datas e horas, títulos, linhas `[Título]`, marcadores de lista e caixas de tarefa `[ ]` / `[x]`, `#tags`, rótulos `chave:`, `**negrito**`, `` `código` `` e setas `⇒ → ->` — e cerca de 20 linguagens de programação recebem comentários, strings, números, palavras-chave, nomes de funções e de tipos. As cores são desenhadas só nas linhas visíveis, então nunca alteram o arquivo nem deixam a digitação lenta. Construções que ocupam várias linhas mantêm a cor até serem fechadas: comentários de bloco (`/* */`, `<!-- -->`), strings de várias linhas (`"""` em Swift e Python, template literals em JavaScript, raw strings em Go, `r#"…"#` em Rust) e blocos de código cercados em Markdown, que são coloridos com a linguagem indicada na string de informação (```` ```python ````). Digitar um delimitador de abertura ou de fechamento recolore imediatamente as linhas abaixo.
- **Gramáticas definidas pelo usuário.** Para colorir uma linguagem que o HyperEdit não conhece, ou para alterar uma integrada, coloque um arquivo `*.json` em `~/Library/Application Support/HyperEdit/grammars/`. O HyperEdit cria a pasta na primeira execução com um `example.json` que você pode copiar e um README que explica cada chave — `name`, `extensions` ou `filenames`, `mode`, `lineComments`, `blockComment`, `strings`, `multilineStrings`, `keywords`, `types`, `constants`, `builtins`, `caseInsensitive`. **Arquivo › Recarregar Gramáticas** aplica suas alterações sem reiniciar; a barra de status mostra o nome da gramática, Comentar (⌘/) usa os marcadores de comentário dela, e um arquivo que não pode ser analisado é ignorado com uma mensagem no painel Saída.

## 16. Temas, fontes e texto CJK

**Temas.** 22 paletas — 5 claras, 17 escuras — vêm com o app. Por padrão ele segue a aparência do sistema: **Hyper Light** no modo claro, **Hyper Dark** no modo escuro. Escolha um tema na aba Layout, no menu de temas da barra de status, em **Visualizar › Tema** ou com ⌥⌘] / ⌥⌘[ para fixá-lo; **Seguir Aparência do Sistema** está nos mesmos menus e nos Ajustes. As mesmas paletas estão disponíveis para o editor Zed (`hyperedit-themes.json` em cada versão lançada).

**Cursor e opacidade da janela.** Ajustes › **Aparência** escolhe a forma do cursor — **Barra** (o padrão), **Bloco** (a célula do caractere é tingida com a cor do cursor para que o glifo continue legível) ou **Sublinhado** — e se ele pisca; os cursores extras do multicursor e do modo coluna usam a mesma forma. A **Opacidade da janela** (50–100 %) deixa a janela inteira translúcida — editor, faixa, painéis e barra de status igualmente — enquanto texto, ícones e bordas continuam sólidos, e **Desfoque atrás da janela** adiciona o desfoque do sistema. Visualizar › Opacidade da Janela tem os passos 100 / 90 / 80 / 70 %.

**Fontes.** O HyperEdit usa **Fira Code** quando ela está instalada e a fonte monoespaçada do sistema caso contrário. O texto coreano é desenhado com uma fonte separada — **D2Coding** por padrão, quando instalada — escalada de modo que uma sílaba Hangul tenha exatamente a largura de duas células latinas, o que mantém retas as tabelas alinhadas por tab. Ligaduras, altura da linha, as duas famílias de fonte e a escala do Hangul estão nos Ajustes. Texto chinês e japonês usa as fontes alternativas do sistema e também conta como duas células em Alinhar Colunas.

## 17. Salvamento, snapshots e codificações

- O **salvamento automático** ocorre dois segundos depois que você para de digitar (⌘S salva agora). Ao encerrar, fechar a janela e trocar de arquivo, o documento é salvo imediatamente, então nada se perde na janela de dois segundos. Toda gravação é atômica.
- **Snapshots.** Antes do primeiro salvamento de cada sessão, uma cópia do arquivo é guardada em `~/Library/Application Support/HyperEdit/snapshots` (**Arquivo › Abrir Pasta de Snapshots**). Os 20 mais recentes de cada arquivo são mantidos e tudo com mais de 90 dias é removido.
- **Alterações externas.** Se outro programa alterar o arquivo enquanto ele está aberto e você não tiver edições não salvas, o HyperEdit o recarrega e mantém o cursor onde estava. Se você tiver edições não salvas, a versão externa vira um snapshot e um aviso é mostrado; salvar então a sobrescreve.
- **Segurança.** Um buffer vazio nunca é gravado por cima de um arquivo que tinha conteúdo. Se salvar falhar ao encerrar, uma cópia de emergência é gravada na pasta de snapshots e você é perguntado se quer encerrar mesmo assim.
- **Codificações.** Os arquivos são lidos primeiro como UTF-8, depois EUC-KR (CP949), CP1252 e Latin-1, e salvos na mesma codificação (um BOM UTF-8 é preservado). Se você digitar um caractere que a codificação original não consegue guardar, o arquivo é salvo como UTF-8 e a barra de status avisa. Um arquivo que não pode ser decodificado em nenhuma dessas codificações não é aberto, em vez de ser danificado.
- **Fins de linha** (UNIX / DOS / MAC) são detectados e preservados; a Adição Rápida e as ferramentas de texto usam o do próprio arquivo.
- **Exportação.** **Arquivo › Exportar como HTML…** salva o documento como um único arquivo HTML autossuficiente — Markdown renderizado como na pré-visualização, notas e código como um bloco com cores de sintaxe — e **Arquivo › Exportar como PDF…** imprime a mesma página em um PDF paginado (Letter nos EUA, no Canadá e no México, A4 nos demais lugares; margens de 36 pt; sem cabeçalho nem rodapé). O painel de salvamento permite escolher o tema (atual, Hyper Light, Hyper Dark) e, para notas e código, os números de linha. A página exportada não contém scripts nem folhas de estilo ou fontes da rede; as URLs das imagens são mantidas como foram escritas, então um navegador (e o renderizador de PDF) pode buscar imagens remotas, e os caminhos relativos de imagens funcionam quando você salva o HTML ao lado do arquivo Markdown. A exportação em PDF funciona para arquivos de até 2 MB. Os blocos secretos (seção 23) são exportados como `••••••••`.

## 18. Referência de ajustes

Abra os Ajustes com **⌘,** ou pela aba Avançado.

| Seção | O que controla |
|---|---|
| Idioma | Idioma da interface (Padrão do Sistema ou um de onze idiomas), **Reiniciar Agora**, **Abrir Guia do Usuário** |
| Fonte | Família da fonte latina, tamanho, ligaduras, altura da linha |
| Hangul | Família da fonte Hangul, a correção de largura 2:1, escala do Hangul; mostra se a fonte está instalada |
| Tema | Seguir aparência do sistema, seletor de tema |
| Arquivos | O arquivo atual, o documento padrão e a pasta de snapshots, com botões para abri-los |
| Adição Rápida | Atalho global (Desativado / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N), cabeçalho de data/hora ativado/desativado |
| Aparência | Estilo do cursor (Barra / Bloco / Sublinhado), piscar, opacidade da janela 50–100 %, desfoque atrás da janela |
| Segredos | Ocultar blocos secretos, ocultar de novo após (10 / 30 / 60 s / Nunca), limpar a área de transferência após copiar um segredo (Desativado / 10 / 30 / 60 s) |
| Bloqueio do App | Exigir Touch ID ou senha para abrir o HyperEdit (desativado), bloquear após inatividade (Nunca / 1 / 5 / 15 / 30 minutos), bloquear quando o Mac entrar em repouso ou a tela for bloqueada (ativado; requer a primeira opção) |

A visibilidade dos painéis, a quebra de linha, os números de linha, as cores de sintaxe, as marcas na barra de rolagem, a divisão e a aba da faixa são lembradas automaticamente.

## 19. Atalhos de teclado

| Atalho | Ação | Atalho | Ação |
|---|---|---|---|
| ⌘N | Novo documento | ⌘O | Abrir |
| ⌘S | Salvar | ⌘F | Buscar |
| ⌘R | Substituir | ⇧⌘F | Buscar em arquivos |
| F3 / ⇧F3 | Ocorrência seguinte / anterior | ⌘L | Ir para a linha |
| ⌃⌘E | Fim do documento | ⌥C | Modo coluna |
| ⌘D | Adicionar próxima ocorrência | ⌥⌘A | Selecionar todas as ocorrências |
| ⌥⌘N | Inserir números | F7 | Inserir data/hora |
| ⌘F2 | Alternar marcador | F2 / ⌥F2 | Marcador seguinte / anterior |
| ⇧⌘K | Apagar linha | ⇧⌘D | Duplicar linha |
| ⌥↑ / ⌥↓ | Mover linha para cima / baixo | ⇧⌘J | Unir linhas |
| ⌃⌘= | Calcular | ⌃⌘T | Alinhar colunas |
| ⌘/ | Comentar / descomentar | ⌃⌘J | Formatar JSON |
| ⇧⌘I | Inserir snippet | Tab | Expandir snippet / próxima parada |
| ⇧⌘M | Gravar / parar macro | ⌥⌘M | Reproduzir macro |
| ⌥⌘← / ⌥⌘→ | Recolher / expandir | ⌥⇧⌘← / ⌥⇧⌘→ | Recolher tudo / expandir tudo |
| ⌘\\ | Dividir editor | ⌥⌘\\ | Focar a outra divisão |
| ⇧⌘N | Adição Rápida | ⌃⌥N | Adição Rápida a partir de qualquer app (configurável) |
| ⌘1 | Barra lateral | ⌘2 | Painel inferior |
| ⌘3 | Estrutura | ⌘4 | Linha do Tempo |
| ⌥⌘L | Números de linha | ⌥Z | Quebra de linha |
| ⇧⌘P | Pré-visualização Markdown | ⌃⌘H | Cores de sintaxe |
| ⌥⌘] / ⌥⌘[ | Tema seguinte / anterior | ⌘= / ⌘- / ⌘0 | Aumentar / diminuir / redefinir zoom |
| ⌥⌘S | Revelar / ocultar blocos secretos | ⌘, | Ajustes |
| ⌃⌘L | Bloquear HyperEdit (Touch ID) | | |
| ⌘Q | Encerrar (salva antes) | | |

## 20. Arquivos que o HyperEdit grava

O HyperEdit só toca nos arquivos que você abre e nos próprios dados:

| Caminho | Conteúdo |
|---|---|
| `~/Documents/HyperEdit/notes.md` | O documento padrão (criado na primeira execução se não existir) |
| `~/Library/Application Support/HyperEdit/snapshots/` | Snapshots feitos antes de salvar e cópias de emergência |
| `~/Library/Application Support/HyperEdit/bookmarks/` | Um arquivo JSON por documento com marcadores |
| `~/Library/Application Support/HyperEdit/snippets.json` | Seus snippets |
| `~/Library/Application Support/HyperEdit/grammars/` | Gramáticas definidas pelo usuário (`*.json`), com `example.json` e um README |
| `~/Library/Application Support/HyperEdit/macros/macros.json` | Macros salvas |
| `~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist` | Preferências, inclusive o idioma da interface |

Nada é gravado ao lado dos seus documentos, e nada sai do seu Mac.

## 21. Solução de problemas

- **O idioma não mudou.** O novo idioma é aplicado depois de reiniciar — use **Reiniciar Agora** nos Ajustes ou encerre e reabra o app. Se o idioma do sistema for um que o HyperEdit não tem, ele mostra inglês; escolha um idioma explicitamente nos Ajustes.
- **Um arquivo não abre.** Arquivos binários abrem no app padrão de propósito. Um arquivo de texto em uma codificação diferente de UTF-8, EUC-KR, CP1252 ou Latin-1 é recusado em vez de ser danificado; converta-o antes com outra ferramenta.
- **O atalho global da Adição Rápida não faz nada.** Outro app pode ser dono da combinação, ou ⌃Space / ⌃⌥Space podem estar reservados à troca de fonte de entrada em Ajustes do Sistema › Teclado. Escolha ⌃⌥N ou ⌃⌥⌘N nos Ajustes. O painel Saída informa o resultado do registro na inicialização.
- **O texto coreano parece largo ou estreito demais nas tabelas.** Instale a D2Coding ou ajuste a escala do Hangul nos Ajustes; a correção de largura 2:1 precisa de uma fonte Hangul monoespaçada.
- **Salvei algo por engano.** Abra a pasta de snapshots (**Arquivo › Abrir Pasta de Snapshots**): a cópia feita antes do primeiro salvamento da sessão está lá, além de qualquer cópia feita quando alterações externas foram detectadas.
- **A faixa mostra só ícones.** A janela está estreita demais para aquela aba; alargue-a ou passe o mouse sobre um ícone para ver o rótulo.

## 22. Limitações conhecidas

- As cores de sintaxe acompanham comentários de bloco, strings de várias linhas e cercas Markdown ao longo das linhas, mas, exceto pelas strings brutas de Rust, só são suportados delimitadores de string iguais na abertura e no fechamento e um par de comentário de bloco por linguagem, e as gramáticas do usuário são listas de palavras sem regras de expressão regular. A pré-visualização Markdown é uma visualização, não um editor.
- As macros gravam só a edição pelo teclado (sem passos de mouse, seleção ou multicursor). Calcular e Alinhar Colunas lidam só com aritmética simples e tabelas com tab / `|`.
- Snippets, macros e gramáticas do usuário são editados como arquivos JSON; não há editor gráfico para eles.
- A exportação grava só o documento inteiro, sem exportação de seleção ou de vários arquivos, opções de página ou de fonte, nem sumário no PDF.
- Os blocos secretos são ocultados só na tela: o arquivo, os salvamentos automáticos e os snapshots são texto simples, a barra de ocultação mostra o comprimento de cada linha, e o VoiceOver ainda lê o texto. Uma cerca secreta precisa começar na margem esquerda (com menos de quatro espaços de recuo, fora de item de lista ou citação), e um bloco cercado aninhado dentro de um bloco secreto precisa de quatro crases na cerca externa. O bloqueio do app esconde a janela e o conteúdo dela do VoiceOver; não criptografa nada.
- Os comentários de bloco não se aninham, e arquivos com finais de linha do Mac clássico (só CR) são coloridos linha por linha. Dentro de um único parágrafo com mais de 20.000 caracteres, os cursores Bloco e Sublinhado voltam ao cursor padrão em barra.
- As regiões recolhidas duram até o fim da sessão e não são salvas por arquivo; arrastar o mouse por uma linha recolhida ainda seleciona o texto oculto.
- Documentos formados por uma única linha de um megabyte ou mais são lentos para abrir e navegar; Minificar JSON avisa antes de produzir um.
- Só arquivos locais; sem sincronização na nuvem e ainda sem app para iOS.
- Idiomas diferentes dos onze listados recorrem ao inglês.

## 23. Blocos secretos e bloqueio do app

**Blocos secretos.** Um bloco de código cercado cuja string de informação começa com `secret` é ocultado no editor:

````markdown
```secret banco
login: me@example.com
senha: hunter2
```
````

Cada linha entre as cercas é desenhada como uma barra vazia com `••••••••`; as linhas da cerca continuam visíveis, para que você veja onde o bloco está e para que serve. A regra é a mesma em arquivos Markdown e de texto simples. Mova o cursor para dentro do bloco — clique nele, use ↑ / ↓, Ir para a Linha, um resultado da busca ou um marcador — e o bloco inteiro é revelado e editável; mova o cursor para fora e ele é ocultado de novo. Só a exibição muda: o texto continua no arquivo, então Buscar, Substituir, desfazer e salvar funcionam exatamente como antes.

- **Revelar Segredos (⌥⌘S)**, no menu Editar, mostra todos os blocos de uma vez; depois de **Ajustes › Segredos › Ocultar de novo após** (10 / 30 / 60 s, padrão 30 s, ou Nunca) eles são ocultados de novo e o painel Saída registra isso. A barra de status mostra `REVEALED` enquanto isso e `•••• N` enquanto N blocos estão ocultos. **Editar › Ocultar Blocos Secretos** desativa a ocultação por completo.
- As linhas secretas aparecem como `••••••••` nas listas de Resultados da Busca e de Buscar em Arquivos (a ocorrência e o número da linha continuam funcionando) e nas prévias dos marcadores, são puladas pela Estrutura e pela Linha do Tempo, e ficam ocultadas na pré-visualização Markdown e nas exportações em HTML / PDF. Sair do HyperEdit executa imediatamente uma limpeza pendente da área de transferência.
- **Limpeza automática da área de transferência.** Quando um copiar ou recortar inclui uma linha secreta — inclusive cópias com multicursor e em modo coluna — a área de transferência é limpa depois de **Ajustes › Segredos › Limpar a área de transferência após copiar um segredo** (Desativado / 10 / 30 / 60 s, padrão 30 s), a menos que você tenha copiado outra coisa nesse meio-tempo. **Editar › Limpar Área de Transferência** a limpa imediatamente, e desativar a ocultação também desativa a limpeza automática.
- Os blocos secretos se recolhem como qualquer bloco cercado (⌥⌘←).

> Ocultar não é criptografar. O arquivo, os salvamentos automáticos e os snapshots são texto simples, e qualquer pessoa que tenha o arquivo pode ler os segredos. O recurso os mantém fora da sua tela, das capturas de tela, dos resultados da busca, da pré-visualização e das exportações enquanto você trabalha.

**Bloqueio do app (Touch ID).** **HyperEdit › Bloquear HyperEdit (⌃⌘L)** (o menu do aplicativo, abaixo de Ajustes…) cobre a janela inteira — faixa, barra lateral, editor, painéis e barra de status — com uma tela de bloqueio opaca no tema atual, fecha uma janela de Ajustes aberta e oculta o painel da Adição Rápida. Nada sobre o documento, nem mesmo o nome do arquivo, é mostrado enquanto bloqueado. Clique em **Desbloquear** (ou pressione Return ou Espaço) para se autenticar com o **Touch ID**; se o Touch ID falhar ou o Mac não tiver um, o macOS recorre à sua senha de login. Bloquear também fecha qualquer diálogo ou alerta aberto, oculta de novo os segredos revelados e executa na hora uma limpeza pendente da área de transferência. Cancelar mantém o HyperEdit bloqueado e o botão tenta de novo.

- **Ajustes › Bloqueio do App.** *Exigir Touch ID ou senha para abrir o HyperEdit* (desativado por padrão) inicia o app bloqueado: o documento é carregado e o salvamento automático continua funcionando, mas nada fica visível até você se autenticar. *Bloquear após inatividade* (Nunca / 1 / 5 / 15 / 30 minutos, padrão Nunca) bloqueia depois desse tempo sem uma tecla pressionada ou um clique no HyperEdit, independentemente da opção de abertura. *Bloquear quando o Mac entrar em repouso ou a tela for bloqueada* (ativado por padrão) vale enquanto a opção de abertura está ativada e também cobre o repouso dos monitores. Uma legenda informa se o Touch ID está disponível neste Mac.
- Enquanto bloqueado, a entrada do teclado é descartada e a barra de menus não pode ser aberta; só ⌘Q, ⌘H / ⌥⌘H, ⌘M, ⌘W, ⌃⌘F e o menu do Dock continuam funcionando. O atalho global da Adição Rápida mostra o pedido de desbloqueio em vez do painel e abre o painel depois que você se autentica.
- Este é um bloqueio de privacidade para a tela, não criptografia: os arquivos no disco permanecem inalterados e legíveis por qualquer outro app. A opção *Exigir…* não pode ser ativada enquanto o Mac não tiver nem Touch ID nem senha de login, para que você não fique trancado do lado de fora.

## 24. Como obter ajuda

- Relatos de bugs e ideias: [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) e [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions).
- Problemas de segurança: veja [SECURITY.md](../../SECURITY.md) para saber como relatar de forma privada.
- Traduções: as strings da interface ficam em `l10n/ui.<idioma>.json` no repositório e este guia em `docs/guide/`; correções são bem-vindas como pull requests — veja [CONTRIBUTING.md](../../CONTRIBUTING.md).

O HyperEdit é software livre sob a Licença MIT. Seu layout é inspirado na faixa de opções clássica do UltraEdit; UltraEdit é uma marca registrada da IDM Computer Solutions, Inc., e o HyperEdit não tem afiliação com a IDM.
