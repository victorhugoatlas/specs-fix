# Specs and Fix

**Specs and Fix** é uma ferramenta de automação em PowerShell para facilitar a manutenção e o diagnóstico de computadores com Windows. Tudo está em **um único arquivo**: `start-specs-and-fix.bat`.

O script coleta informações de hardware e oferece rotinas de limpeza de arquivos temporários e reparo de arquivos corrompidos do sistema.

## Requisitos
- Windows 10 ou 11
- Windows PowerShell 5.1 (já incluído no Windows)
- Permissão de Administrador (o próprio arquivo solicita)

## Como utilizar
1. Baixe o arquivo `start-specs-and-fix.bat`.
2. Dê dois cliques nele (aceite o pedido de administrador).
3. Escolha uma opção no menu:
   - `[1]` Limpeza de arquivos temporários
   - `[2]` Reparo do sistema
   - `[3]` Executar tudo
   - `[0]` Sair

### Modo direto (sem menu)
Também é possível executar pelo terminal:

```
start-specs-and-fix.bat limpeza
start-specs-and-fix.bat reparo
start-specs-and-fix.bat tudo
start-specs-and-fix.bat tudo /y
```

O parâmetro `/y` pula as confirmações.

## Funcionalidades

### Diagnóstico de hardware
- Hostname, fabricante/modelo, sistema operacional (build e status de ativação) e uptime
- Processador (núcleos/threads), placa-mãe, chipset e BIOS
- RAM: total, slots ocupados, tipo (DDR3/4/5), frequência em uso
- Todos os discos (tipo, modelo, tamanho, saúde e vida útil quando disponível), com o disco do sistema identificado
- Espaço livre por volume
- Placa de vídeo (adaptadores virtuais são ignorados)
- Identificação de tipo: Notebook, Desktop ou Máquina Virtual
- Aviso de reinicialização pendente

### Módulo 1: Limpeza
Remove arquivos de:
- `Temp` (Windows e usuário)
- Cache de Chrome e Edge (todos os perfis) e Firefox
- Cache de download do Windows Update e relatórios de erro (WER)
- `Prefetch` (opcional, perguntado na execução)
- Lixeira

Ao final, informa quanto espaço foi liberado. Se houver navegadores abertos, oferece fechá-los.

### Módulo 2: Reparo
1. Cria um ponto de restauração
2. `DISM /Online /Cleanup-Image /RestoreHealth`
3. `sfc /scannow`
4. `chkdsk C: /scan` (verificação online, sem reiniciar)
5. Opcional: agenda `chkdsk C: /f /r` para o próximo boot

O código de saída de cada etapa é verificado e informado.

## Relatório
O arquivo `SPECS_AND_FIX_[NOME_DO_PC].txt` é salvo na mesma pasta do `.bat` (ou na Área de Trabalho, se a pasta não permitir gravação). Ele contém o relatório de hardware e o **registro de manutenção** com data e hora de cada etapa executada.

## Aviso
- A limpeza apaga arquivos de forma definitiva.
- Salve seus arquivos abertos antes dos módulos de reparo; a verificação profunda do `chkdsk` exige reinicialização.
- Use por sua conta e risco.

---

*by Victor Hugo*
